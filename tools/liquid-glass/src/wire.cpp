#include "wire.hpp"
#include "liquid-glass-server.h"
#include <algorithm>
#include <array>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <unordered_map>
#include <wayland-server-core.h>

namespace GlassWire {
namespace {
struct Surface {
    wl_listener destroyed{};
    wl_resource* resource = nullptr;
    Geometry pending, current;
};
struct Server {
    wl_listener destroyed{};
    wl_global* global = nullptr;
    void (*bound)(wl_resource*) = nullptr;
    std::unordered_map<wl_resource*, std::unique_ptr<Surface>> surfaces;
};
Server* server = nullptr;

void surfaceDestroyed(wl_listener* listener, void*) {
    auto* surface = reinterpret_cast<Surface*>(listener); // first member
    wl_list_remove(&surface->destroyed.link);
    server->surfaces.erase(surface->resource);
}
void setGeometry(wl_client*, wl_resource* manager, wl_resource* resource, int32_t width, int32_t height, uint32_t valid,
                 wl_array* array) {
    constexpr size_t fields = 6, recordSize = fields * sizeof(int32_t);
    if (!server || array->size % recordSize || array->size > 64 * recordSize || width < 0 || height < 0 ||
        width > 32768 || height > 32768 || valid > 1) {
        wl_resource_post_error(manager, 0, "invalid glass geometry");
        return;
    }
    Geometry next;
    next.valid = valid;
    next.width = width;
    next.height = height;
    for (size_t offset = 0; offset < array->size; offset += recordSize) {
        std::array<int32_t, fields> values;
        std::memcpy(values.data(), static_cast<char*>(array->data) + offset, recordSize);
        Shape s{wl_fixed_to_double(values[0]), wl_fixed_to_double(values[1]), wl_fixed_to_double(values[2]),
                wl_fixed_to_double(values[3]), wl_fixed_to_double(values[4]), wl_fixed_to_double(values[5])};
        if (s.width <= 0 || s.height <= 0 || s.width > 32768 || s.height > 32768 || s.radius < 0 ||
            s.radius > std::min(s.width, s.height) / 2.0 + 0.01 || s.opacity < 0 || s.opacity > 1) {
            wl_resource_post_error(manager, 0, "invalid glass rectangle");
            return;
        }
        next.shapes.push_back(s);
    }
    auto& slot = server->surfaces[resource];
    const bool created = !slot;
    if (created) {
        slot = std::make_unique<Surface>();
        slot->resource = resource;
        slot->destroyed.notify = surfaceDestroyed;
        wl_resource_add_destroy_listener(resource, &slot->destroyed);
    }
    next.serial = slot->pending.serial + 1;
    slot->pending = std::move(next);
    if (created && server->bound)
        server->bound(resource);
}
void destroyManager(wl_client*, wl_resource* resource) { wl_resource_destroy(resource); }
const struct ian_liquid_glass_v1_interface implementation = {destroyManager, setGeometry};
void bind(wl_client* client, void*, uint32_t version, uint32_t id) {
    auto* resource = wl_resource_create(client, &ian_liquid_glass_v1_interface, std::min(version, 1u), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &implementation, nullptr, nullptr);
}
void displayDestroyed(wl_listener* listener, void*) {
    auto* state = reinterpret_cast<Server*>(listener);
    state->bound = nullptr;
    for (auto& [_, surface] : state->surfaces)
        wl_list_remove(&surface->destroyed.link);
    wl_list_remove(&state->destroyed.link);
    if (state->global)
        wl_global_destroy(state->global);
    server = nullptr;
    delete state;
}
} // namespace
void start(wl_display* display, void (*onBound)(wl_resource*)) {
    if (!server) {
        server = new Server;
        server->destroyed.notify = displayDestroyed;
        wl_display_add_destroy_listener(display, &server->destroyed);
    }
    if (!server->global) {
        server->global = wl_global_create(display, &ian_liquid_glass_v1_interface, 1, nullptr, bind);
        if (!server->global)
            throw std::runtime_error("glass protocol allocation failed");
    }
    server->bound = onBound;
    for (auto& [resource, surface] : server->surfaces) {
        surface->current.valid = false;
        surface->current.serial = 0;
        onBound(resource);
    }
}
void stop() {
    if (!server)
        return;
    server->bound = nullptr;
    // Withdraw the global, but let already-bound objects drain safely. Their
    // callbacks live in this small display-lifetime transport, not the plugin.
    if (server->global) {
        wl_global_destroy(server->global);
        server->global = nullptr;
    }
    for (auto& [_, surface] : server->surfaces)
        surface->current.valid = false;
}
Geometry pending(wl_resource* resource) {
    if (!server)
        return {};
    const auto it = server->surfaces.find(resource);
    return it == server->surfaces.end() ? Geometry{} : it->second->pending;
}
void apply(wl_resource* resource, const Geometry& geometry) {
    if (!server)
        return;
    const auto it = server->surfaces.find(resource);
    if (it != server->surfaces.end())
        it->second->current = geometry;
}
Geometry geometry(wl_resource* resource) {
    if (!server)
        return {};
    const auto it = server->surfaces.find(resource);
    return it == server->surfaces.end() ? Geometry{} : it->second->current;
}
} // namespace GlassWire
