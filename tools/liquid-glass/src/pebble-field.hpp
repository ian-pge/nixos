#pragma once
#include "profile-field.hpp"
#include <GLES3/gl3.h>
#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstdint>
#include <numbers>
#include <stdexcept>
#include <vector>

// Shared by the compositor and standalone GPU/parity tests. All calls require
// a current GL context; the caller owns/restores native compositor GL state.
namespace PebbleField {
using Key = ProfileField::Key;
inline Key key(float width, float height, float radius, float scale) {
    const float shortest = std::max(std::min(width, height) / (2 * scale), 0.01F);
    const auto q = [](float n) { return std::round(n * 4096) / 4096; };
    const float r = std::clamp(radius / scale / shortest, 0.F, 1.F);
    const float remaining = r - std::min(r * 0.4F, 0.12F);
    return {q(width / (2 * scale * shortest)), q(height / (2 * scale * shortest)), q(r),
            remaining >= 0.25F / shortest ? 0.F : q(0.25F / shortest)};
}
struct Mesh {
    GLuint vao = 0, vertices = 0, indices = 0;
    GLsizei count = 0;
    Key current;
    bool valid = false;
    void init(Key key = {1, 1, 1, 0}) {
        if (valid && current == key)
            return;
        constexpr int rings = 112, samples = 64, stride = 3 * (samples - 1) + 2, sectors = stride - 1;
        std::vector<float> data{1, 1, 0};
        std::vector<uint16_t> index;
        for (int ring = 1; ring <= rings; ++ring) {
            const float t = 1.F - float(ring) / rings;
            const double u = t * t, start = std::min(double(key.radius) * .4, .12);
            double e = 1e-6;
            if (u > start) {
                const double v = (u - start) / (1 - start),
                             blend = std::clamp(v * v * v * (10 + v * (-15 + 6 * v)), 0., 1.);
                const double a = 1 - u + (key.x - 1) * (1 - blend), b = 1 - u + (key.y - 1) * (1 - blend);
                const double remaining = key.radius - start,
                             at = (u - start) / std::max({remaining, double(key.floor), 1e-7});
                const double r =
                    std::clamp((1 - blend) * (1 - blend) * remaining / (1 + at + at * at) + blend * std::min(a, b), 0.,
                               std::min(a, b));
                const double ax = a - r, by = b - r,
                             ratio = std::max(ax, by) > 0 ? std::min(ax, by) / std::max(ax, by) : 0;
                const double wanted = .45 * blend;
                if (ratio > 0 && wanted > 0)
                    e = std::max(e, wanted * ratio / (wanted + ratio));
            }
            // Union samples from the two ellipses' parametric angles and the
            // circle. This resolves both long sides and tight corners without
            // a costly ray search at every vertex or lost precision near pi/2.
            std::vector<std::array<double, 2>> normals{{1, 0}, {0, 1}};
            for (int i = 1; i < samples; ++i) {
                double angle = double(i) / samples * std::numbers::pi * .5, c = std::cos(angle), s = std::sin(angle);
                for (auto n : {std::array{c, s}, std::array{c, e * s}, std::array{e * c, s}}) {
                    const double length = std::hypot(n[0], n[1]);
                    normals.push_back({n[0] / length, n[1] / length});
                }
            }
            std::sort(normals.begin(), normals.end(), [](auto a, auto b) { return a[1] * b[0] < b[1] * a[0]; });
            for (auto normal : normals) {
                data.push_back(u);
                data.push_back(normal[0]);
                data.push_back(normal[1]);
            }
        }
        for (int angle = 0; angle < sectors; ++angle) {
            index.insert(index.end(), {0, uint16_t(1 + angle), uint16_t(2 + angle)});
            for (int ring = 1; ring < rings; ++ring) {
                const uint16_t a = 1 + (ring - 1) * stride + angle, b = a + stride;
                index.insert(index.end(), {a, b, uint16_t(b + 1), a, uint16_t(b + 1), uint16_t(a + 1)});
            }
        }
        count = index.size();
        if (!vao)
            glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        if (!vertices)
            glGenBuffers(1, &vertices);
        glBindBuffer(GL_ARRAY_BUFFER, vertices);
        glBufferData(GL_ARRAY_BUFFER, data.size() * sizeof(float), data.data(), GL_STATIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(float), nullptr);
        if (!indices)
            glGenBuffers(1, &indices);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indices);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, index.size() * sizeof(uint16_t), index.data(), GL_STATIC_DRAW);
        current = key;
        valid = true;
    }
    void release() {
        if (vertices)
            glDeleteBuffers(1, &vertices);
        if (indices)
            glDeleteBuffers(1, &indices);
        if (vao)
            glDeleteVertexArrays(1, &vao);
        vao = vertices = indices = 0;
        count = 0;
        valid = false;
    }
};
using Atlas = ProfileField::Atlas;
} // namespace PebbleField
