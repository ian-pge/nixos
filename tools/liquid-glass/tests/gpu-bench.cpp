// Offscreen fragment-shader A/B test. No Hyprland plugin or desktop capture.
// Usage: glass-gpu-bench BASELINE_SHADER_DIR CANDIDATE_SHADER_DIR [RENDERER]
//        [CANDIDATE_FRAGMENT] [BASELINE_FRAGMENT] [cached]
// Gaussian refresh is included unless "cached" is requested. Timing excludes
// capture and QML, and uses the same full test texture for both versions.
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>

// The extension declarations require the core GL types above.
#include "../src/cushion-field.hpp"
#include "../src/pebble-field.hpp"
#include <GLES2/gl2ext.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr int width = 5120, height = 900, batch = 8, rounds = 24;

std::string read(const std::string& path) {
    std::ifstream file(path);
    if (!file)
        throw std::runtime_error("Cannot read " + path);
    return {std::istreambuf_iterator<char>(file), {}};
}

GLuint shader(GLenum type, const std::string& source) {
    GLuint id = glCreateShader(type);
    const char* text = source.c_str();
    glShaderSource(id, 1, &text, nullptr);
    glCompileShader(id);
    GLint ok = 0;
    glGetShaderiv(id, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        std::array<char, 4096> error{};
        glGetShaderInfoLog(id, error.size(), nullptr, error.data());
        throw std::runtime_error(error.data());
    }
    return id;
}

GLuint link(const std::string& vertex, const std::string& fragment) {
    const auto vs = shader(GL_VERTEX_SHADER, vertex);
    const auto fs = shader(GL_FRAGMENT_SHADER, fragment);
    const auto id = glCreateProgram();
    glAttachShader(id, vs);
    glAttachShader(id, fs);
    glLinkProgram(id);
    glDeleteShader(vs);
    glDeleteShader(fs);
    GLint ok = 0;
    glGetProgramiv(id, GL_LINK_STATUS, &ok);
    if (!ok)
        throw std::runtime_error("Cannot link benchmark shader");
    return id;
}
GLuint program(const std::string& directory, const std::string& fragment = "glass.frag") {
    const auto vertex = fragment == "pebble-field.frag"    ? "/pebble-field.vert"
                        : fragment == "cushion-field.frag" ? "/cushion-field.vert"
                        : fragment == "analytic.frag" || fragment == "previous.frag" || fragment == "pebble.frag"
                            ? "/analytic.vert"
                            : "/fullscreen.vert";
    const auto id = link(read(directory + vertex), read(directory + "/" + fragment));
    glUseProgram(id);
    for (auto [name, unit] : {std::pair{"background", 0},
                              {"content", 1},
                              {"boundaries", 2},
                              {"blurredBackground", 3},
                              {"pebbleProfiles", 2},
                              {"surfaceProfiles", 2}})
        glUniform1i(glGetUniformLocation(id, name), unit);
    glUniform2f(glGetUniformLocation(id, "resolution"), width, height);
    glUniform4f(glGetUniformLocation(id, "contentRect"), 0, 0, 1, 1);
    return id;
}

struct Context {
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface surface = EGL_NO_SURFACE;
    ~Context() { reset(); }
    void reset() {
        if (display == EGL_NO_DISPLAY)
            return;
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (surface != EGL_NO_SURFACE)
            eglDestroySurface(display, surface);
        if (context != EGL_NO_CONTEXT)
            eglDestroyContext(display, context);
        eglTerminate(display);
        display = EGL_NO_DISPLAY;
        context = EGL_NO_CONTEXT;
        surface = EGL_NO_SURFACE;
    }
    void open(const std::string& wanted) {
        const auto devices = reinterpret_cast<PFNEGLQUERYDEVICESEXTPROC>(eglGetProcAddress("eglQueryDevicesEXT"));
        const auto platform =
            reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(eglGetProcAddress("eglGetPlatformDisplayEXT"));
        if (!devices || !platform)
            throw std::runtime_error("EGL device enumeration unavailable");
        std::array<EGLDeviceEXT, 16> list{};
        EGLint count = 0;
        if (!devices(list.size(), list.data(), &count))
            throw std::runtime_error("Cannot enumerate EGL devices");
        for (int i = 0; i < count; ++i) {
            display = platform(EGL_PLATFORM_DEVICE_EXT, list[i], nullptr);
            if (!eglInitialize(display, nullptr, nullptr)) {
                reset();
                continue;
            }
            eglBindAPI(EGL_OPENGL_ES_API);
            const EGLint attributes[] = {EGL_SURFACE_TYPE,
                                         EGL_PBUFFER_BIT,
                                         EGL_RENDERABLE_TYPE,
                                         EGL_OPENGL_ES3_BIT,
                                         EGL_RED_SIZE,
                                         8,
                                         EGL_GREEN_SIZE,
                                         8,
                                         EGL_BLUE_SIZE,
                                         8,
                                         EGL_ALPHA_SIZE,
                                         8,
                                         EGL_NONE};
            EGLConfig config;
            EGLint configs = 0;
            if (!eglChooseConfig(display, attributes, &config, 1, &configs) || !configs) {
                reset();
                continue;
            }
            const EGLint contextAttributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
            const EGLint surfaceAttributes[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
            context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttributes);
            surface = eglCreatePbufferSurface(display, config, surfaceAttributes);
            if (!eglMakeCurrent(display, surface, surface, context)) {
                reset();
                continue;
            }
            const std::string renderer = reinterpret_cast<const char*>(glGetString(GL_RENDERER));
            if ((!wanted.empty() && renderer.find(wanted) == std::string::npos) ||
                renderer.find("llvmpipe") != std::string::npos) {
                reset();
                continue;
            }
            std::cout << "GPU: " << renderer << '\n';
            GLint extensions = 0;
            glGetIntegerv(GL_NUM_EXTENSIONS, &extensions);
            for (int n = 0; n < extensions; ++n)
                if (std::string(reinterpret_cast<const char*>(glGetStringi(GL_EXTENSIONS, n))) ==
                    "GL_EXT_disjoint_timer_query")
                    return;
            throw std::runtime_error("GL_EXT_disjoint_timer_query unavailable; no CPU-time substitute");
        }
        throw std::runtime_error("Requested hardware renderer not found");
    }
};

float rounded(float x, float y, float cx, float cy, float hw, float hh, float radius) {
    float qx = std::abs(x - cx) - hw + radius, qy = std::abs(y - cy) - hh + radius;
    return std::hypot(std::max(qx, 0.F), std::max(qy, 0.F)) + std::min(std::max(qx, qy), 0.F) - radius;
}
float distance(float x, float y, int scene) {
    if (scene == 2)
        return -rounded(x, y, width / 2.F, height / 2.F, width / 2.F - 40, height / 2.F - 40, 32);
    float d = 10000;
    for (int i = 0; i < 8; ++i)
        d = std::min(d, rounded(x, y, 310.F + i * 640, 70, 250, 28, 28));
    if (scene == 1)
        d = std::min(d, rounded(x, y, width / 2.F, 495, 350, 365, 30));
    return -d;
}

std::vector<std::array<float, 5>> boxes(int scene) {
    if (scene == 2)
        return {{{40, 40, width - 80, height - 80, 32}}};
    std::vector<std::array<float, 5>> result;
    for (int i = 0; i < 8; ++i)
        result.push_back({60.F + i * 640, 42, 500, 56, 28});
    if (scene == 1)
        result.push_back({width / 2.F - 350, 130, 700, 730, 30});
    return result;
}

GLuint texture(int unit, int w, int h, bool floating, const void* data) {
    GLuint id;
    glGenTextures(1, &id);
    glActiveTexture(GL_TEXTURE0 + unit);
    glBindTexture(GL_TEXTURE_2D, id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, floating ? GL_RGBA16F : GL_RGBA8, w, h, 0, GL_RGBA,
                 floating ? GL_FLOAT : GL_UNSIGNED_BYTE, data);
    return id;
}

double median(std::vector<double> values) {
    std::sort(values.begin(), values.end());
    return (values[(values.size() - 1) / 2] + values[values.size() / 2]) / 2;
}

template <class Mesh>
int probeProfile(const std::string& directory, const std::string& fixturePath, const std::string& renderer,
                 bool cushion) {
    Context context;
    context.open(renderer);
    const auto fieldProgram = program(directory, cushion ? "cushion-field.frag" : "pebble-field.frag");
    const auto probeProgram = link(read(directory + "/fullscreen.vert"), R"GLSL(#version 300 es
precision highp float;
uniform highp sampler2DArray profiles;
uniform vec2 point;
uniform vec2 halfSize;
uniform float radius;
uniform bool cushion;
out vec4 color;
void main() {
    float shortest=min(halfSize.x,halfSize.y);
    vec2 bodyRadius=48.0+2.0*(halfSize-shortest);
    float peak=8.0+dot(halfSize*halfSize,0.5/bodyRadius);
    vec2 at=abs(point)/halfSize;
    vec4 f=texture(profiles,vec3(at,0));
    vec2 weights=min(at*vec2(textureSize(profiles,0).xy)*2.0,vec2(1));
    if(cushion) f.w=sqrt(max(f.w,0.0));
    vec3 n=vec3(f.xy*weights*sign(point)*peak/shortest,cushion?f.w:f.z);
    n=dot(n,n)>1e-10?normalize(n):vec3(0,0,1);
    vec2 q=abs(point)-halfSize+radius, outside=max(q,vec2(0));
    float len=length(outside),d=max(radius-len-min(max(q.x,q.y),0.0),0.0);
    float rim=min(radius*0.4,shortest*0.12);
    if(!cushion && d<rim) {
        vec2 outwards=len>1e-5?sign(point)*outside/len:(q.x>q.y?vec2(sign(point.x),0):vec2(0,sign(point.y)));
        float u=d/shortest; f.w=sqrt(u*(2.0-u));
        n=normalize(vec3(outwards*peak*(1.0-u),shortest*f.w));
    }
    color=vec4(n,f.w);
}
)GLSL");
    GLuint vao, fb, output;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    glGenFramebuffers(1, &fb);
    glBindFramebuffer(GL_FRAMEBUFFER, fb);
    glGenTextures(1, &output);
    glBindTexture(GL_TEXTURE_2D, output);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, 1, 1, 0, GL_RGBA, GL_FLOAT, nullptr);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, output, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        throw std::runtime_error("probe framebuffer incomplete");
    glDisable(GL_BLEND);
    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_DEPTH_TEST);
    Mesh mesh;
    mesh.init();
    PebbleField::Atlas atlas;
    const auto getTime =
        reinterpret_cast<PFNGLGETQUERYOBJECTUI64VEXTPROC>(eglGetProcAddress("glGetQueryObjectui64vEXT"));
    GLuint timer;
    glGenQueries(1, &timer);
    std::vector<double> generationCPU, generationGPU;
    std::ifstream fixture(fixturePath);
    if (!fixture)
        throw std::runtime_error("missing profile fixtures");
    float w, h, r, scale, x, y, nx, ny, nz, z;
    double maxOffset = 0, maxHeight = 0, sum = 0;
    int count = 0;
    while (fixture >> w >> h >> r >> scale >> x >> y >> nx >> ny >> nz >> z) {
        int size = std::clamp(int(std::bit_ceil(unsigned(std::ceil(std::max(w, h) * scale * 0.5)))), 256, 1024);
        if (cushion)
            size = CushionField::resolution(w * scale, h * scale, r * scale);
        atlas.allocate(size, 1);
        glViewport(0, 0, size, size);
        const auto profileKey = cushion ? CushionField::key(w * scale, h * scale, r * scale, scale)
                                        : PebbleField::key(w * scale, h * scale, r * scale, scale);
        if (!atlas.valid[0] || !(atlas.keys[0] == profileKey)) {
            const auto started = std::chrono::steady_clock::now();
            mesh.init(profileKey);
            generationCPU.push_back(
                std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count());
            glBeginQuery(GL_TIME_ELAPSED_EXT, timer);
            atlas.update(0, profileKey, fieldProgram, mesh);
            glEndQuery(GL_TIME_ELAPSED_EXT);
            GLuint64 elapsed = 0;
            getTime(timer, GL_QUERY_RESULT, &elapsed);
            generationGPU.push_back(double(elapsed) / 1e6);
        }
        glBindFramebuffer(GL_FRAMEBUFFER, fb);
        glViewport(0, 0, 1, 1);
        glBindVertexArray(vao);
        glUseProgram(probeProgram);
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D_ARRAY, atlas.texture);
        glUniform1i(glGetUniformLocation(probeProgram, "profiles"), 2);
        glUniform2f(glGetUniformLocation(probeProgram, "point"), x, y);
        glUniform2f(glGetUniformLocation(probeProgram, "halfSize"), w / 2, h / 2);
        glUniform1f(glGetUniformLocation(probeProgram, "radius"), r);
        glUniform1i(glGetUniformLocation(probeProgram, "cushion"), cushion);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        std::array<float, 4> pixels{};
        glReadPixels(0, 0, 1, 1, GL_RGBA, GL_FLOAT, pixels.data());
        if (glGetError() != GL_NO_ERROR)
            throw std::runtime_error("GL error reading pebble probe");
        const double offset = 36 * std::hypot(pixels[0] - nx, pixels[1] - ny);
        const double height = std::abs(pixels[3] - z);
        if (!std::isfinite(offset) || !std::isfinite(height))
            throw std::runtime_error("nonfinite pebble field");
        if (offset > 0.75 || height > 0.008)
            std::cout << "probe mismatch " << w << 'x' << h << " radius=" << r << " at " << x << ',' << y
                      << " offset=" << offset << " height=" << height << " normal=" << pixels[0] << ',' << pixels[1]
                      << ',' << pixels[2] << " expected=" << nx << ',' << ny << ',' << nz << '\n';
        maxOffset = std::max(maxOffset, offset);
        maxHeight = std::max(maxHeight, height);
        sum += offset;
        count++;
    }
    std::cout << (cushion ? "Cushion" : "Pebble") << " parity: " << count
              << " probes; max displacement error=" << maxOffset << " logical px; mean=" << sum / std::max(count, 1)
              << "; max normalized-height error=" << maxHeight << '\n';
    if (!generationCPU.empty())
        std::cout << "Profile generation (cache misses only): CPU median=" << median(generationCPU)
                  << " ms; GPU median=" << median(generationGPU) << " ms\n";
    glDeleteQueries(1, &timer);
    atlas.release();
    mesh.release();
    glDeleteProgram(fieldProgram);
    glDeleteProgram(probeProgram);
    glDeleteFramebuffers(1, &fb);
    glDeleteTextures(1, &output);
    glDeleteVertexArrays(1, &vao);
    if (count < 50 || maxOffset > 0.75 || maxHeight > 0.008)
        return 1;
    return 0;
}
} // namespace

int main(int argc, char** argv) {
    try {
        if (argc >= 4 && std::string{argv[1]} == "--probe-pebble")
            return probeProfile<PebbleField::Mesh>(argv[2], argv[3], argc > 4 ? argv[4] : "NVIDIA", false);
        if (argc >= 4 && std::string{argv[1]} == "--probe-cushion")
            return probeProfile<CushionField::Mesh>(argv[2], argv[3], argc > 4 ? argv[4] : "NVIDIA", true);
        if (argc < 3)
            throw std::runtime_error("Usage: glass-gpu-bench BASELINE_SHADER_DIR CANDIDATE_SHADER_DIR [RENDERER] "
                                     "[CANDIDATE_FRAGMENT] [BASELINE_FRAGMENT] [cached]");
        Context context;
        context.open(argc > 3 ? argv[3] : "");
        const auto getTime =
            reinterpret_cast<PFNGLGETQUERYOBJECTUI64VEXTPROC>(eglGetProcAddress("glGetQueryObjectui64vEXT"));
        if (!getTime)
            throw std::runtime_error("64-bit GPU timer unavailable");
        const std::array<std::string, 2> fragments{argc > 5 ? argv[5] : "glass.frag",
                                                   argc > 4 ? argv[4] : "glass.frag"};
        const std::array programs{program(argv[1], fragments[0]), program(argv[2], fragments[1])};
        const std::array<bool, 2> cushion{glGetUniformLocation(programs[0], "surfaceProfiles") >= 0,
                                          glGetUniformLocation(programs[1], "surfaceProfiles") >= 0};
        const std::array<bool, 2> pebble{cushion[0] || glGetUniformLocation(programs[0], "pebbleProfiles") >= 0,
                                         cushion[1] || glGetUniformLocation(programs[1], "pebbleProfiles") >= 0};
        const std::array<GLuint, 2> profilePrograms{
            pebble[0] ? program(argv[1], cushion[0] ? "cushion-field.frag" : "pebble-field.frag") : 0,
            pebble[1] ? program(argv[2], cushion[1] ? "cushion-field.frag" : "pebble-field.frag") : 0};
        PebbleField::Mesh profileMesh;
        CushionField::Mesh cushionMesh;
        std::array<PebbleField::Atlas, 2> profiles;
        if (pebble[0] || pebble[1])
            profileMesh.init();
        const std::array<bool, 2> blurred{glGetUniformLocation(programs[0], "blurredBackground") >= 0,
                                          glGetUniformLocation(programs[1], "blurredBackground") >= 0};
        const std::array<GLuint, 2> blurPrograms{blurred[0] ? program(argv[1], "blur.frag") : 0,
                                                 blurred[1] ? program(argv[2], "blur.frag") : 0};
        const bool cached = argc > 6 && std::string{argv[6]} == "cached";
        std::cout << "Blur refresh: " << (cached ? "cached" : "included each draw") << '\n';
        GLuint vao, framebuffer, query;
        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        glGenFramebuffers(1, &framebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
        const auto output = texture(4, width, height, false, nullptr);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, output, 0);
        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
            throw std::runtime_error("Incomplete benchmark framebuffer");
        glViewport(0, 0, width, height);
        glDisable(GL_BLEND);
        glDisable(GL_SCISSOR_TEST);
        glDisable(GL_DEPTH_TEST);
        glGenQueries(1, &query);
        GLuint blurFB;
        glGenFramebuffers(1, &blurFB);
        const std::array blurTextures{texture(3, width / 2, height / 2, false, nullptr),
                                      texture(3, width / 2, height / 2, false, nullptr)};
        std::vector<unsigned char> background(width * height * 4), front(background.size());
        std::vector<float> field((width / 2) * (height / 2) * 4);
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x) {
                const auto i = (y * width + x) * 4;
                background[i] = (x * 17 + y * 7) % 256;
                background[i + 1] = (x * 3 + y * 13) % 256;
                background[i + 2] = (x * 11 + y * 5) % 256;
                background[i + 3] = 255;
            }
        const auto bg = texture(0, width, height, false, background.data());
        bool faster = true;
        for (int scene = 0; scene < 3; ++scene) {
            const auto geometry = boxes(scene);
            int resolution = 256;
            for (const auto& box : geometry)
                resolution = std::max(resolution, int(std::ceil(std::max(box[2], box[3]) * .5)));
            resolution = std::min(1024U, std::bit_ceil(unsigned(resolution)));
            for (int side = 0; side < 2; side++)
                if (pebble[side])
                    profiles[side].allocate(resolution, geometry.size());
            for (int side = 0; side < 2; ++side)
                if (fragments[side] == "analytic.frag" || fragments[side] == "pebble.frag") {
                    std::array<float, 64 * 4> rectangles{};
                    std::array<float, 64> radii{};
                    for (size_t i = 0; i < geometry.size(); ++i) {
                        std::copy_n(geometry[i].begin(), 4, rectangles.begin() + i * 4);
                        radii[i] = geometry[i][4];
                    }
                    glUseProgram(programs[side]);
                    glUniform4fv(glGetUniformLocation(programs[side], "shapes"), geometry.size(), rectangles.data());
                    glUniform1fv(glGetUniformLocation(programs[side], "radii"), geometry.size(), radii.data());
                }
            float blurScale = 1.0F;
            std::array<bool, 2> blurReady{};
            const auto draw = [&](int which) {
                if (pebble[which]) {
                    glViewport(0, 0, resolution, resolution);
                    for (size_t i = 0; i < geometry.size(); i++) {
                        const auto& box = geometry[i];
                        if (cushion[which])
                            profiles[which].update(i, CushionField::key(box[2], box[3], box[4], blurScale),
                                                   profilePrograms[which], cushionMesh);
                        else
                            profiles[which].update(i, PebbleField::key(box[2], box[3], box[4], blurScale),
                                                   profilePrograms[which], profileMesh);
                    }
                    glActiveTexture(GL_TEXTURE2);
                    glBindTexture(GL_TEXTURE_2D_ARRAY, profiles[which].texture);
                    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
                    glViewport(0, 0, width, height);
                    glBindVertexArray(vao);
                }
                if (blurred[which] && (!cached || !blurReady[which])) {
                    glUseProgram(blurPrograms[which]);
                    glUniform1i(glGetUniformLocation(blurPrograms[which], "source"), 0);
                    glBindFramebuffer(GL_FRAMEBUFFER, blurFB);
                    glViewport(0, 0, width / 2, height / 2);
                    glActiveTexture(GL_TEXTURE0);
                    const float step = 1.75F * blurScale;
                    for (int pass = 0; pass < 2; ++pass) {
                        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, blurTextures[pass],
                                               0);
                        glBindTexture(GL_TEXTURE_2D, pass == 0 ? bg : blurTextures[0]);
                        glUniform2f(glGetUniformLocation(blurPrograms[which], "direction"),
                                    pass == 0 ? step / width : 0, pass == 1 ? step / height : 0);
                        glDrawArrays(GL_TRIANGLES, 0, 3);
                    }
                    glBindTexture(GL_TEXTURE_2D, bg);
                    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
                    glViewport(0, 0, width, height);
                    blurReady[which] = true;
                }
                glUseProgram(programs[which]);
                if (fragments[which] == "analytic.frag" || fragments[which] == "pebble.frag")
                    glDrawArraysInstanced(GL_TRIANGLES, 0, 6, geometry.size());
                else
                    glDrawArrays(GL_TRIANGLES, 0, 3);
            };
            for (int y = 0; y < height; ++y)
                for (int x = 0; x < width; ++x) {
                    const auto i = (y * width + x) * 4;
                    const float d = distance(x + .5F, y + .5F, scene);
                    const auto a = static_cast<unsigned char>(std::clamp(d + .5F, 0.F, 1.F) * 31);
                    for (int c = 0; c < 3; ++c)
                        front[i + c] = a * (24 + c * 6) / 255;
                    front[i + 3] = a;
                    if (d > 4 && x % 37 < 3 && y % 23 < 4)
                        for (int c = 0; c < 4; ++c)
                            front[i + c] = 255;
                }
            for (int y = 0; y < height / 2; ++y)
                for (int x = 0; x < width / 2; ++x)
                    field[(y * (width / 2) + x) * 4] = distance(x * 2.F + 1, y * 2.F + 1, scene);
            const auto content = texture(1, width, height, false, front.data());
            const auto boundaries = texture(2, width / 2, height / 2, true, field.data());
            for (float scale : {1.F, 1.6F}) {
                blurScale = scale;
                blurReady.fill(false);
                for (auto p : programs) {
                    glUseProgram(p);
                    glUniform1f(glGetUniformLocation(p, "scale"), scale);
                }
                for (int i = 0; i < 64; ++i) {
                    glUseProgram(programs[i % 2]);
                    draw(i % 2);
                }
                glFinish();
                std::array<std::vector<double>, 2> times;
                std::vector<double> ratios;
                for (int round = 0; round < rounds; ++round) {
                    std::array<double, 2> pair{};
                    for (int side = 0; side < 2; ++side) {
                        const int which = (round + side) % 2;
                        glUseProgram(programs[which]);
                        glBeginQuery(GL_TIME_ELAPSED_EXT, query);
                        for (int i = 0; i < batch; ++i)
                            draw(which);
                        glEndQuery(GL_TIME_ELAPSED_EXT);
                        GLuint64 duration = 0;
                        getTime(query, GL_QUERY_RESULT, &duration);
                        pair[which] = static_cast<double>(duration) / batch / 1e6;
                        times[which].push_back(pair[which]);
                    }
                    ratios.push_back(pair[1] / pair[0]);
                }
                GLint disjoint = 0;
                glGetIntegerv(GL_GPU_DISJOINT_EXT, &disjoint);
                if (disjoint || glGetError() != GL_NO_ERROR)
                    throw std::runtime_error("Invalid/disjoint GPU measurement");
                const double ratio = median(ratios);
                faster &= ratio <= 1.0;
                std::cout << "scene=" << scene << " scale=" << scale << " baseline_ms=" << median(times[0])
                          << " candidate_ms=" << median(times[1]) << " paired_ratio=" << ratio << '\n';
            }
            glDeleteTextures(1, &content);
            glDeleteTextures(1, &boundaries);
        }
        glDeleteTextures(1, &bg);
        for (auto& atlas : profiles)
            atlas.release();
        profileMesh.release();
        cushionMesh.release();
        for (auto p : profilePrograms)
            if (p)
                glDeleteProgram(p);
        glDeleteTextures(blurTextures.size(), blurTextures.data());
        glDeleteFramebuffers(1, &blurFB);
        for (auto p : blurPrograms)
            if (p)
                glDeleteProgram(p);
        glDeleteTextures(1, &output);
        glDeleteFramebuffers(1, &framebuffer);
        glDeleteVertexArrays(1, &vao);
        glDeleteQueries(1, &query);
        for (auto p : programs)
            glDeleteProgram(p);
        std::cout << (faster ? "PASS: no median GPU-time regression in the paired cases\n"
                             : "FAIL: GPU-time regression; do not activate candidate\n");
        return faster ? 0 : 2;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
