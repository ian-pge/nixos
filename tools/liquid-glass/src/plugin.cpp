#include "shaders.hpp"
#include "wire.hpp"
#include <GLES3/gl3.h>
#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/gl/GLFramebuffer.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <memory>
#include <stdexcept>
#include <unordered_map>

using namespace Render;
using namespace Render::GL;
using namespace Desktop::View;

namespace {
HANDLE handle = nullptr;
CFunctionHook* hook = nullptr;
bool enabled = true;
uint64_t frames = 0;
uint64_t backgroundCopies = 0, contentUpdates = 0, copiedPixels = 0, referencePixels = 0, compositedPixels = 0;
uint64_t analyticFrames = 0, rasterFrames = 0;
std::string lastError;
CHyprSignalListener preRender;
CHyprSignalListener cleanupRender;
SP<SHyprCtlCommand> statusCommand;
using LayerFunction = void (*)(IHyprRenderer*, PHLLS, PHLMONITOR, const Time::steady_tp&, bool, bool);

bool supported(PHLLS layer) {
    return layer && (layer->m_namespace == "quickshell-top-bar" || layer->m_namespace == "liquid-glass-test");
}

void announce(bool ready) {
    if (g_pEventManager)
        g_pEventManager->postEvent({"custom", ready ? "liquid-glass:ready" : "liquid-glass:disabled"});
}

GLuint compile(GLenum type, const char* source) {
    const auto shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        std::array<char, 2048> error{};
        glGetShaderInfoLog(shader, error.size(), nullptr, error.data());
        glDeleteShader(shader);
        throw std::runtime_error(error.data());
    }
    return shader;
}

GLuint program(const char* fragment, const char* vertex = shaders::vertex) {
    auto vs = compile(GL_VERTEX_SHADER, vertex);
    auto fs = compile(GL_FRAGMENT_SHADER, fragment);
    auto id = glCreateProgram();
    glAttachShader(id, vs);
    glAttachShader(id, fs);
    glLinkProgram(id);
    glDeleteShader(vs);
    glDeleteShader(fs);
    GLint ok = 0;
    glGetProgramiv(id, GL_LINK_STATUS, &ok);
    if (!ok) {
        std::array<char, 2048> error{};
        glGetProgramInfoLog(id, error.size(), nullptr, error.data());
        glDeleteProgram(id);
        throw std::runtime_error(error.data());
    }
    return id;
}

// Raw GL resources exist only on the compositor render thread/context.
struct Target {
    GLuint texture = 0, fb = 0;
    int width = 0, height = 0;
    void release() {
        if (fb)
            glDeleteFramebuffers(1, &fb);
        if (texture)
            glDeleteTextures(1, &texture);
        fb = texture = 0;
        width = height = 0;
    }
    void resize(int w, int h, bool floating) {
        if (w == width && h == height)
            return;
        release();
        width = w;
        height = h;
        glGenTextures(1, &texture);
        glBindTexture(GL_TEXTURE_2D, texture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, floating ? GL_NEAREST : GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, floating ? GL_NEAREST : GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, floating ? GL_RGBA16F : GL_RGBA8, w, h, 0, GL_RGBA,
                     floating ? GL_HALF_FLOAT : GL_UNSIGNED_BYTE, nullptr);
        glGenFramebuffers(1, &fb);
        glBindFramebuffer(GL_FRAMEBUFFER, fb);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
            throw std::runtime_error("incomplete glass framebuffer");
    }
};

struct Resources {
    PHLLSREF layer;
    PHLMONITORREF monitor;
    CHyprSignalListener commit;
    bool dirty = true;
    bool backdropDirty = true;
    bool analytic = false;
    Target background, mask[2];
    SP<IFramebuffer> content;
    int maskResult = 0;
    Vector2D position;
    Vector2D size, targetSize;
    CBox area;
    float alpha = -1;
    float scale = -1;
    wl_output_transform transform = WL_OUTPUT_TRANSFORM_NORMAL;
    void release() {
        commit.reset();
        background.release();
        for (auto& m : mask)
            m.release();
        content.reset();
    }
};
std::unordered_map<CLayerSurface*, std::unique_ptr<Resources>> resources;
GLuint seedProgram = 0, distanceProgram = 0, resolveProgram = 0, smoothProgram = 0, glassProgram = 0,
       analyticProgram = 0, vao = 0;

struct GeometryObserver {
    struct Frame {
        WP<SSurfaceState> state;
        WP<CWLCallbackResource> marker;
        GlassWire::Geometry geometry;
    };
    CHyprSignalListener queued, applied, destroyed;
    std::vector<Frame> frames;
};
std::unordered_map<wl_resource*, std::unique_ptr<GeometryObserver>> geometryObservers;

void observeGeometry(wl_resource* resource) {
    auto surface = CWLSurfaceResource::fromResource(resource);
    if (!surface || geometryObservers.contains(resource))
        return;
    auto observer = std::make_unique<GeometryObserver>();
    auto* ptr = observer.get();
    observer->queued = surface->m_events.stateCommit.listen([ptr, resource](WP<SSurfaceState> state) {
        std::erase_if(ptr->frames, [](const auto& f) { return f.state.expired(); });
        if (!state || !state->updated.bits.buffer || !state->buffer)
            return;
        WP<CWLCallbackResource> marker;
        if (!state->callbacks.empty())
            marker = state->callbacks.back();
        ptr->frames.push_back({state, marker, GlassWire::pending(resource)});
    });
    observer->applied = surface->m_events.commit.listen([ptr, resource, weak = WP<CWLSurfaceResource>{surface}] {
        auto current = weak.lock();
        if (!current || !current->m_current.updated.bits.buffer)
            return;
        GlassWire::Geometry geometry;
        for (auto it = ptr->frames.begin(); it != ptr->frames.end();) {
            if (!it->state || !it->marker) {
                it = ptr->frames.erase(it);
                continue;
            }
            // updateFrom moves the callbacks to m_current before commit.emit.
            // Match that exact buffer, never newer metadata waiting on a fence.
            const bool applied = it->state->callbacks.empty() &&
                                 std::ranges::any_of(current->m_current.callbacks,
                                                     [&](const auto& cb) { return cb.get() == it->marker.get(); });
            if (applied) {
                geometry = it->geometry;
                it = ptr->frames.erase(it);
            } else
                ++it;
        }
        // If a client supplies no identifiable frame, use the proven raster path.
        GlassWire::apply(resource, geometry);
    });
    observer->destroyed = surface->m_events.destroy.listen([resource] { geometryObservers.erase(resource); });
    geometryObservers.emplace(resource, std::move(observer));
}

GlassWire::Geometry geometryFor(PHLLS layer, PHLMONITOR monitor) {
    auto surface = layer->wlSurface()->resource();
    auto geometry = GlassWire::geometry(surface->getResource()->resource());
    if (!geometry.valid || geometry.width <= 0 || geometry.height <= 0 ||
        surface->m_current.size != Vector2D{double(geometry.width), double(geometry.height)})
        return {};
    const auto size = layer->size(IGeometric::GEOMETRIC_CURRENT);
    const double sx = size.x / geometry.width, sy = size.y / geometry.height;
    if (std::abs(sx - sy) > 0.001)
        return {};
    const auto pos = layer->position(IGeometric::GEOMETRIC_CURRENT) - monitor->m_position;
    for (auto& shape : geometry.shapes) {
        CBox box{pos.x + shape.x * sx, pos.y + shape.y * sy, shape.width * sx, shape.height * sy};
        box.scale(monitor->m_scale);
        if (monitor->m_transform != WL_OUTPUT_TRANSFORM_NORMAL)
            box.transform(Math::wlTransformToHyprutils(Math::invertTransform(monitor->m_transform)),
                          monitor->m_transformedSize.x, monitor->m_transformedSize.y);
        shape.x = box.x;
        shape.y = box.y;
        shape.width = box.width;
        shape.height = box.height;
        shape.radius *= sx * monitor->m_scale;
    }
    return geometry;
}

Resources& resourceFor(PHLLS layer) {
    auto& entry = resources[layer.get()];
    if (!entry) {
        entry = std::make_unique<Resources>();
        entry->layer = layer;
        entry->monitor = layer->m_monitor;
        entry->commit = layer->wlSurface()->resource()->m_events.commit.listen([ptr = entry.get()] {
            ptr->dirty = true;
            ptr->backdropDirty = true;
        });
    }
    return *entry;
}

// Bound the *surface*, not its input region: hit testing is not a visual mask.
// Keep a conservative path on rotated outputs, and a halo for refraction and
// filtering. Align to the half-resolution mask grid to avoid moving its seeds.
CBox effectArea(PHLLS layer, PHLMONITOR monitor) {
    const auto screen = monitor->m_pixelSize;
    if (monitor->m_transform != WL_OUTPUT_TRANSFORM_NORMAL)
        return {0, 0, screen.x, screen.y};
    auto p = (layer->position(IGeometric::GEOMETRIC_CURRENT) - monitor->m_position) * monitor->m_scale;
    auto s = layer->size(IGeometric::GEOMETRIC_CURRENT) * monitor->m_scale;
    const auto geometry = geometryFor(layer, monitor);
    if (geometry.valid && !geometry.shapes.empty()) {
        CRegion region;
        for (const auto& shape : geometry.shapes)
            region.add(CBox{shape.x, shape.y, shape.width, shape.height}.expand(2));
        const auto box = region.getExtents();
        p = box.pos();
        s = box.size();
    }
    const double halo = 40.0 * monitor->m_scale;
    const double x1 = std::clamp(std::floor((p.x - halo) / 2.0) * 2.0, 0.0, screen.x);
    const double y1 = std::clamp(std::floor((p.y - halo) / 2.0) * 2.0, 0.0, screen.y);
    const double x2 = std::clamp(std::ceil((p.x + s.x + halo) / 2.0) * 2.0, 0.0, screen.x);
    const double y2 = std::clamp(std::ceil((p.y + s.y + halo) / 2.0) * 2.0, 0.0, screen.y);
    return {x1, y1, x2 - x1, y2 - y1};
}

void prepareMonitor(PHLMONITOR monitor) {
    if (!enabled || !monitor->m_damage.hasChanged() || g_pSessionLockManager->isSessionLocked())
        return;
    const auto changed = monitor->m_damage.getBufferDamage(1);
    for (auto& [_, entry] : resources) {
        auto layer = entry->layer.lock();
        if (entry->monitor == monitor && (!layer || !layer->visible() || layer->m_monitor != monitor))
            monitor->m_damage.damage(entry->area);
    }
    for (const auto& group : monitor->m_layerSurfaceLayers) {
        for (const auto& weak : group) {
            auto layer = weak.lock();
            if (!supported(layer) || !layer->visible())
                continue;
            auto& r = resourceFor(layer);
            const auto area = effectArea(layer, monitor);
            r.dirty |= r.monitor != monitor || r.area != area || r.targetSize != monitor->m_pixelSize ||
                       r.position != layer->position(IGeometric::GEOMETRIC_CURRENT) ||
                       r.size != layer->size(IGeometric::GEOMETRIC_CURRENT) || r.scale != monitor->m_scale ||
                       r.alpha != layer->alpha()[LS_ALPHA_FADE]->value() || r.transform != monitor->m_transform;
            if (monitor->m_transform != WL_OUTPUT_TRANSFORM_NORMAL) {
                r.backdropDirty = true;
                monitor->m_damage.damageEntire();
                continue;
            }
            r.backdropDirty |= r.dirty || !changed.copy().intersect(area).empty();
            if (!r.backdropDirty)
                continue;
            // Refresh the entire sampled halo before copying it. Never capture
            // the previous frame's glass from an undamaged framebuffer region.
            monitor->m_damage.damage(area);
            if (r.monitor == monitor && r.area != area)
                monitor->m_damage.damage(r.area);
        }
    }
}

// Do not leave GL state altered for the next native Hyprland render pass.
struct GLState {
    GLint drawFB, readFB, viewport[4], scissor[4], active, prog, vertexArray, textures[3];
    GLboolean blend, scissorEnabled, stencil, depth, mask[4];
    GLfloat clearColor[4];
    GLState() {
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawFB);
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readFB);
        glGetIntegerv(GL_VIEWPORT, viewport);
        glGetIntegerv(GL_SCISSOR_BOX, scissor);
        glGetIntegerv(GL_ACTIVE_TEXTURE, &active);
        glGetIntegerv(GL_CURRENT_PROGRAM, &prog);
        glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vertexArray);
        glGetBooleanv(GL_COLOR_WRITEMASK, mask);
        glGetFloatv(GL_COLOR_CLEAR_VALUE, clearColor);
        blend = glIsEnabled(GL_BLEND);
        scissorEnabled = glIsEnabled(GL_SCISSOR_TEST);
        stencil = glIsEnabled(GL_STENCIL_TEST);
        depth = glIsEnabled(GL_DEPTH_TEST);
        for (int i = 0; i < 3; ++i) {
            glActiveTexture(GL_TEXTURE0 + i);
            glGetIntegerv(GL_TEXTURE_BINDING_2D, &textures[i]);
        }
        glActiveTexture(GL_TEXTURE0);
    }
    void afterNativeDraw() {
        // drawContent uses Hyprland's renderer and updates its internal caches.
        // Restore THIS native state after our raw GL passes, not the state from
        // before drawContent (which may refer to a different texture shader).
        glGetIntegerv(GL_CURRENT_PROGRAM, &prog);
        glGetIntegerv(GL_VIEWPORT, viewport);
        glGetIntegerv(GL_SCISSOR_BOX, scissor);
        blend = glIsEnabled(GL_BLEND);
        scissorEnabled = glIsEnabled(GL_SCISSOR_TEST);
        stencil = glIsEnabled(GL_STENCIL_TEST);
        depth = glIsEnabled(GL_DEPTH_TEST);
    }
    ~GLState() {
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawFB);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, readFB);
        g_pHyprOpenGL->setViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
        g_pHyprOpenGL->scissor(scissor[0], scissor[1], scissor[2], scissor[3], false);
        for (auto [cap, value] : {std::pair{GL_BLEND, blend},
                                  {GL_SCISSOR_TEST, scissorEnabled},
                                  {GL_STENCIL_TEST, stencil},
                                  {GL_DEPTH_TEST, depth}})
            g_pHyprOpenGL->setCapStatus(cap, value);
        glColorMask(mask[0], mask[1], mask[2], mask[3]);
        glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
        for (int i = 0; i < 3; ++i) {
            glActiveTexture(GL_TEXTURE0 + i);
            glBindTexture(GL_TEXTURE_2D, textures[i]);
        }
        glActiveTexture(active);
        glUseProgram(prog);
        glBindVertexArray(vertexArray);
    }
};

void texture(GLuint prog, const char* name, int unit, GLuint tex) {
    glActiveTexture(GL_TEXTURE0 + unit);
    glBindTexture(GL_TEXTURE_2D, tex);
    glUniform1i(glGetUniformLocation(prog, name), unit);
}
void pair(GLuint prog, const char* name, float x, float y) { glUniform2f(glGetUniformLocation(prog, name), x, y); }
void scalar(GLuint prog, const char* name, float x) { glUniform1f(glGetUniformLocation(prog, name), x); }
void contentRect(GLuint prog, const CBox& area, int w, int h) {
    glUniform4f(glGetUniformLocation(prog, "contentRect"), area.x / w, area.y / h, area.width / w, area.height / h);
}

void drawContent(PHLLS layer, PHLMONITOR monitor, const Time::steady_tp& now, const CRegion& damage) {
    CSurfacePassElement::SRenderData data;
    data.pMonitor = monitor;
    data.when = now;
    data.pos = layer->position(IGeometric::GEOMETRIC_CURRENT);
    const auto size = layer->size(IGeometric::GEOMETRIC_CURRENT);
    data.w = size.x;
    data.h = size.y;
    data.fadeAlpha = layer->alpha()[LS_ALPHA_FADE]->value();
    data.pLS = layer;
    data.decorate = false;
    data.blur = false;
    data.clipBox = CBox{0, 0, monitor->m_size.x, monitor->m_size.y}.scale(monitor->m_scale).round();
    const auto root = layer->wlSurface()->resource();
    root->breadthfirst(
        [&](SP<CWLSurfaceResource> surface, const Vector2D& offset, void*) {
            if (!surface->m_current.texture || surface->m_current.size.x < 1 || surface->m_current.size.y < 1)
                return;
            data.surface = surface;
            data.texture = surface->m_current.texture;
            data.localPos = offset;
            data.mainSurface = surface == root;
            g_pHyprRenderer->draw(data, damage);
            ++data.surfaceCounter;
        },
        nullptr);
}

void renderGlass(PHLLS layer, PHLMONITOR monitor, const Time::steady_tp& now, const CBox& area) {
    GLState glState;
    const auto saved = g_pHyprRenderer->m_renderData;
    const auto target = saved.currentFB;
    if (!target || !target->isAllocated())
        throw std::runtime_error("missing render target");
    const int w = target->m_size.x, h = target->m_size.y;
    auto restore = Hyprutils::Utils::CScopeGuard([&] { g_pHyprRenderer->m_renderData = saved; });
    if (!glassProgram) {
        seedProgram = program(shaders::seed);
        distanceProgram = program(shaders::distance);
        resolveProgram = program(shaders::resolve);
        smoothProgram = program(shaders::smooth);
        glassProgram = program(shaders::glass);
        analyticProgram = program(shaders::analytic, shaders::analyticVertex);
        glGenVertexArrays(1, &vao);
    }
    auto& r = resourceFor(layer);
    const auto geometry = geometryFor(layer, monitor);
    const bool analytic = geometry.valid && !geometry.shapes.empty();
    if (r.analytic != analytic)
        r.dirty = true;
    const int rw = area.width, rh = area.height;
    if (rw <= 0 || rh <= 0)
        return;
    if (r.area != area || r.targetSize != Vector2D{w, h}) {
        r.dirty = true;
        r.backdropDirty = true;
    }
    r.background.resize(rw, rh, false);
    g_pHyprRenderer->disableScissor();
    if (r.backdropDirty) {
        glBindFramebuffer(GL_READ_FRAMEBUFFER, glState.drawFB);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, r.background.fb);
        glBlitFramebuffer(area.x, area.y, area.x + rw, area.y + rh, 0, 0, rw, rh, GL_COLOR_BUFFER_BIT, GL_NEAREST);
        ++backgroundCopies;
        copiedPixels += uint64_t(rw) * rh;
        r.backdropDirty = false;
    }
    if (r.dirty) {
        if (!r.content)
            r.content = g_pHyprRenderer->createFB("liquid-glass-content");
        // Keep the native content framebuffer in monitor coordinates. This
        // preserves Hyprland's projection/colour management; only our backdrop
        // and distance targets are cropped. Native content is cached as well.
        r.content->alloc(w, h, target->m_drmFormat);
        r.content->setImageDescription(target->imageDescription());
        r.content->bind();
        g_pHyprRenderer->m_renderData.currentFB = r.content;
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);
        drawContent(layer, monitor, now, CRegion{area});
        glState.afterNativeDraw();
        ++contentUpdates;
    }
    g_pHyprRenderer->m_renderData = saved;
    g_pHyprOpenGL->setCapStatus(GL_BLEND, false);
    g_pHyprOpenGL->setCapStatus(GL_SCISSOR_TEST, false);
    g_pHyprOpenGL->setCapStatus(GL_STENCIL_TEST, false);
    g_pHyprOpenGL->setCapStatus(GL_DEPTH_TEST, false);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glBindVertexArray(vao);
    if (r.dirty && !analytic) {
        const int mw = (rw + 1) / 2, mh = (rh + 1) / 2;
        for (auto& m : r.mask) {
            m.resize(mw, mh, true);
            glBindTexture(GL_TEXTURE_2D, m.texture);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        }
        glBindFramebuffer(GL_FRAMEBUFFER, r.mask[0].fb);
        g_pHyprOpenGL->setViewport(0, 0, mw, mh);
        glUseProgram(seedProgram);
        texture(seedProgram, "content", 0, r.content->getTexture()->m_texID);
        pair(seedProgram, "maskSize", mw, mh);
        contentRect(seedProgram, area, w, h);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        int source = 0;
        const auto propagate = [&](int jump) {
            glBindFramebuffer(GL_FRAMEBUFFER, r.mask[1 - source].fb);
            glUseProgram(distanceProgram);
            texture(distanceProgram, "seeds", 0, r.mask[source].texture);
            pair(distanceProgram, "maskSize", mw, mh);
            scalar(distanceProgram, "jump", jump);
            glDrawArrays(GL_TRIANGLES, 0, 3);
            source = 1 - source;
        };
        // The body lens also needs valid distances deep inside expanded
        // panels. Cover the entire mask rather than just a fixed rim radius.
        // This field remains cached between Quickshell commits.
        for (auto jump = std::bit_floor(static_cast<unsigned>(std::max(mw, mh))); jump; jump /= 2)
            propagate(jump);
        propagate(1);
        glBindFramebuffer(GL_FRAMEBUFFER, r.mask[1 - source].fb);
        glUseProgram(resolveProgram);
        texture(resolveProgram, "seeds", 0, r.mask[source].texture);
        texture(resolveProgram, "content", 1, r.content->getTexture()->m_texID);
        pair(resolveProgram, "resolution", rw, rh);
        contentRect(resolveProgram, area, w, h);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        source = 1 - source;
        glUseProgram(smoothProgram);
        for (auto direction : {std::pair{1.0F, 0.0F}, std::pair{0.0F, 1.0F}}) {
            glBindFramebuffer(GL_FRAMEBUFFER, r.mask[1 - source].fb);
            texture(smoothProgram, "field", 0, r.mask[source].texture);
            pair(smoothProgram, "direction", direction.first, direction.second);
            glDrawArrays(GL_TRIANGLES, 0, 3);
            source = 1 - source;
        }
        r.maskResult = source;
        r.dirty = false;
        glBindTexture(GL_TEXTURE_2D, r.mask[r.maskResult].texture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    }
    if (analytic) {
        for (auto& mask : r.mask)
            mask.release();
        r.dirty = false;
    }
    glBindFramebuffer(GL_FRAMEBUFFER, glState.drawFB);
    g_pHyprOpenGL->setViewport(area.x, area.y, rw, rh);
    const auto material = analytic ? analyticProgram : glassProgram;
    glUseProgram(material);
    texture(material, "background", 0, r.background.texture);
    texture(material, "content", 1, r.content->getTexture()->m_texID);
    if (!analytic)
        texture(material, "boundaries", 2, r.mask[r.maskResult].texture);
    pair(material, "resolution", rw, rh);
    contentRect(material, area, w, h);
    scalar(material, "scale", monitor->m_scale);
    if (analytic) {
        std::array<float, 64 * 4> boxes{};
        std::array<float, 64> radii{};
        for (size_t i = 0; i < geometry.shapes.size(); ++i) {
            const auto& shape = geometry.shapes[i];
            boxes[i * 4] = shape.x - area.x;
            boxes[i * 4 + 1] = shape.y - area.y;
            boxes[i * 4 + 2] = shape.width;
            boxes[i * 4 + 3] = shape.height;
            radii[i] = shape.radius;
        }
        glUniform4fv(glGetUniformLocation(material, "shapes"), geometry.shapes.size(), boxes.data());
        glUniform1fv(glGetUniformLocation(material, "radii"), geometry.shapes.size(), radii.data());
    }
    // Buffer-age repairs can revisit only part of this surface. The cached
    // pristine backdrop remains valid; do not overwrite undamaged pixels or
    // higher layers outside this pass's damage.
    auto damage =
        monitor->m_transform == WL_OUTPUT_TRANSFORM_NORMAL ? saved.damage.copy().intersect(area) : CRegion{area};
    const auto draw = [&](const CRegion& region) {
        region.forEachRect([&](const auto& rect) {
            g_pHyprOpenGL->scissor(rect.x1, rect.y1, rect.x2 - rect.x1, rect.y2 - rect.y1, false);
            if (analytic)
                glDrawArraysInstanced(GL_TRIANGLES, 0, 6, geometry.shapes.size());
            else
                glDrawArrays(GL_TRIANGLES, 0, 3);
            compositedPixels += uint64_t(rect.x2 - rect.x1) * (rect.y2 - rect.y1);
        });
    };
    if (analytic) {
        CRegion visible;
        for (const auto& shape : geometry.shapes)
            visible.add(CBox{shape.x, shape.y, shape.width, shape.height}.expand(2));
        draw(damage.copy().intersect(visible));
        ++analyticFrames;
    } else {
        draw(damage);
        ++rasterFrames;
    }
    r.analytic = analytic;
    r.area = area;
    r.targetSize = {w, h};
    r.monitor = monitor;
    r.position = layer->position(IGeometric::GEOMETRIC_CURRENT);
    r.size = layer->size(IGeometric::GEOMETRIC_CURRENT);
    r.scale = monitor->m_scale;
    r.transform = monitor->m_transform;
    r.alpha = layer->alpha()[LS_ALPHA_FADE]->value();
    referencePixels += uint64_t(w) * h;
    ++frames;
}

class GlassPass final : public IPassElement {
    PHLLS layer;
    PHLMONITOR monitor;
    Time::steady_tp now;
    CBox area;

  public:
    GlassPass(PHLLS l, PHLMONITOR m, Time::steady_tp t) : layer(l), monitor(m), now(t), area(effectArea(l, m)) {}
    bool needsLiveBlur() override { return true; }
    bool needsPrecomputeBlur() override { return false; }
    bool disableSimplification() override { return monitor->m_transform != WL_OUTPUT_TRANSFORM_NORMAL; }
    const char* passName() override { return "LiquidGlassPass"; }
    ePassElementType type() override { return EK_CUSTOM; }
    std::optional<CBox> boundingBox() override {
        if (monitor->m_transform != WL_OUTPUT_TRANSFORM_NORMAL)
            return CBox{0, 0, monitor->m_size.x, monitor->m_size.y};
        return area.copy().scale(1.0 / monitor->m_scale);
    }
    std::vector<UP<IPassElement>> draw() override {
        try {
            if (enabled)
                renderGlass(layer, monitor, now, area);
            else
                drawContent(layer, monitor, now, g_pHyprRenderer->m_renderData.damage);
        } catch (const std::exception& error) {
            lastError = error.what();
            enabled = false;
            announce(false);
            Log::logger->log(Log::ERR, "Liquid Glass disabled: {}", lastError);
            drawContent(layer, monitor, now, g_pHyprRenderer->m_renderData.damage);
        }
        return {};
    }
};

void renderLayer(IHyprRenderer* renderer, PHLLS layer, PHLMONITOR monitor, const Time::steady_tp& now, bool popups,
                 bool lockscreen) {
    if (!enabled || !supported(layer) || popups || lockscreen || !layer->visible() || renderer->m_bRenderingSnapshot ||
        g_pSessionLockManager->isSessionLocked()) {
        reinterpret_cast<LayerFunction>(hook->m_original)(renderer, layer, monitor, now, popups, lockscreen);
        return;
    }
    renderer->m_renderPass.add(makeUnique<GlassPass>(layer, monitor, now));
}
} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE h) {
    handle = h;
    enabled = true;
    frames = backgroundCopies = contentUpdates = copiedPixels = referencePixels = compositedPixels = 0;
    analyticFrames = rasterFrames = 0;
    lastError.clear();
    if (std::string_view(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("Liquid Glass: Hyprland ABI mismatch");
    if (g_pHyprRenderer->type() != IHyprRenderer::RT_GL)
        throw std::runtime_error("Liquid Glass requires the OpenGL renderer");
    const auto matches = HyprlandAPI::findFunctionsByName(handle, "renderLayer");
    for (const auto& m : matches) {
        if (m.demangled.starts_with("Render::IHyprRenderer::renderLayer(")) {
            hook = HyprlandAPI::createFunctionHook(handle, m.address, reinterpret_cast<void*>(&renderLayer));
            break;
        }
    }
    if (!hook || !hook->hook())
        throw std::runtime_error("Liquid Glass: unsupported renderLayer entry point");
    preRender = Event::bus()->m_events.render.pre.listen(prepareMonitor);
    cleanupRender = Event::bus()->m_events.render.stage.listen([](eRenderStage stage) {
        if (stage != RENDER_BEGIN)
            return;
        std::erase_if(resources, [](auto& entry) {
            auto layer = entry.second->layer.lock();
            if (enabled && layer && layer->m_mapped)
                return false;
            entry.second->release();
            return true;
        });
    });
    statusCommand = HyprlandAPI::registerHyprCtlCommand(
        handle, {"liquidglass", false, [](eHyprCtlOutputFormat, std::string request) {
                     if (request == "liquidglass enable" || request == "liquidglass disable") {
                         const bool requested = request == "liquidglass enable";
                         if (requested && !lastError.empty())
                             return std::string{"error: reload the plugin after a rendering failure"};
                         enabled = requested;
                         for (auto& [_, r] : resources) {
                             r->dirty = true;
                             r->backdropDirty = true;
                         }
                         announce(enabled);
                         for (const auto& monitor : State::monitorState()->monitors())
                             g_pHyprRenderer->damageMonitor(monitor);
                         return std::string{"ok"};
                     }
                     if (request == "liquidglass reset-stats") {
                         frames = backgroundCopies = contentUpdates = copiedPixels = referencePixels =
                             compositedPixels = 0;
                         analyticFrames = rasterFrames = 0;
                         return std::string{"ok"};
                     }
                     if (request != "liquidglass")
                         return std::string{"error: use liquidglass [enable|disable|reset-stats]"};
                     return std::format(
                         "{{\"enabled\":{},\"frames\":{},\"surfaces\":{},\"version\":1,"
                         "\"backgroundCopies\":{},\"contentUpdates\":{},\"copiedPixels\":{},"
                         "\"referencePixels\":{},\"compositedPixels\":{},\"analyticFrames\":{},\"rasterFrames\":{}}}",
                         enabled ? "true" : "false", frames, resources.size(), backgroundCopies, contentUpdates,
                         copiedPixels, referencePixels, compositedPixels, analyticFrames, rasterFrames);
                 }});
    GlassWire::start(g_pCompositor->m_wlDisplay, observeGeometry);
    announce(true);
    return {"liquid-glass", "Live glass backgrounds for the Quickshell bar", "local", "0.2.3"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    GlassWire::stop();
    geometryObservers.clear();
    enabled = false;
    announce(false);
    preRender.reset();
    cleanupRender.reset();
    if (hook)
        hook->unhook();
    // The render pass retains the previous frame's elements until the next
    // frame. Destroy our vtables before dlclose, not in that later frame.
    g_pHyprRenderer->m_renderPass.removeAllOfType("LiquidGlassPass");
    if (statusCommand) {
        HyprlandAPI::unregisterHyprCtlCommand(handle, statusCommand);
        statusCommand.reset();
    }
    if (g_pHyprOpenGL) {
        eglMakeCurrent(g_pHyprOpenGL->m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, g_pHyprOpenGL->m_eglContext);
        for (auto& [_, r] : resources)
            r->release();
        resources.clear();
        for (auto p : {seedProgram, distanceProgram, resolveProgram, smoothProgram, glassProgram, analyticProgram})
            if (p)
                glDeleteProgram(p);
        if (vao)
            glDeleteVertexArrays(1, &vao);
        seedProgram = distanceProgram = resolveProgram = smoothProgram = glassProgram = analyticProgram = vao = 0;
    }
    for (const auto& monitor : State::monitorState()->monitors())
        g_pHyprRenderer->damageMonitor(monitor);
}
