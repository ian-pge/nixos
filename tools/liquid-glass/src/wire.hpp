#pragma once
#include <cstdint>
#include <vector>

struct wl_display;
struct wl_resource;

namespace GlassWire {
struct Shape {
    double x, y, width, height, radius, opacity;
};
struct Geometry {
    bool valid = false;
    int width = 0, height = 0;
    uint64_t serial = 0;
    std::vector<Shape> shapes;
};
// This transport has display lifetime, independent of the render plugin. Its
// inert handlers must remain callable while clients observe plugin unloading.
void start(wl_display* display, void (*onBound)(wl_resource*));
void stop();
Geometry pending(wl_resource* surface);
void apply(wl_resource* surface, const Geometry& geometry);
Geometry geometry(wl_resource* surface);
} // namespace GlassWire
