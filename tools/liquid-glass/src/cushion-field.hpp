#pragma once
#include "profile-field.hpp"
#include <array>
#include <cmath>
#include <cstdint>
#include <numbers>

namespace CushionField {
using Key = ProfileField::Key;
using Atlas = ProfileField::Atlas;
inline int resolution(float width, float height, float radius) {
    // Tiny radii need several texels across their retained rim, not just one
    // texel per screen pixel. Normal widget radii retain the previous budget.
    const float half = std::max(width, height) * .5F;
    const float cornerResolution = 6 * half / std::max(radius, .25F);
    const float needed = std::max(half, cornerResolution);
    // Only exceptionally tight corners may exceed the usual 1024 cap.
    return std::clamp(int(std::bit_ceil(unsigned(std::ceil(needed)))), 256, cornerResolution > 1024 ? 2048 : 1024);
}
inline Key key(float width, float height, float radius, float scale) {
    const float shortest = std::max(std::min(width, height) / (2 * scale), 0.01F);
    // Preserve subpixel radii: coarse rounding of a 1 px corner noticeably
    // changes its limiting normal. Ordinary radii keep the animation cache's
    // previous tolerance; tiny corners use the finer normalized key.
    const float normalizedRadius = std::clamp(radius / scale / shortest, 0.F, 1.F);
    const float precision = normalizedRadius < .02F ? 65536.F : 4096.F;
    const auto q = [precision](float n) { return std::round(n * precision) / precision; };
    return {q(width / (2 * scale * shortest)), q(height / (2 * scale * shortest)), q(normalizedRadius), 0};
}

struct Mesh {
    static constexpr int modes = 96, boundarySamples = 2048;
    GLuint vao = 0, vertices = 0, indices = 0;
    GLsizei count = 0;
    Key current;
    bool valid = false;
    std::array<float, modes * 2> coefficients{};

    void init(Key key = {1, 1, 1, 0}) {
        if (valid && current == key)
            return;
        // Same Fourier integration as the approved viewer model. Only the
        // normalized outline matters, so movement/bounce reuses the atlas.
        std::array<double, modes * 2> sums{};
        for (int i = 0; i < boundarySamples; i++) {
            const double angle = 2 * std::numbers::pi * i / boundarySamples;
            const double c0 = std::cos(angle), s0 = std::sin(angle), c = std::abs(c0), s = std::abs(s0);
            double t = std::min(key.x / std::max(c, 1e-15), key.y / std::max(s, 1e-15));
            if (t * c > key.x - key.radius && t * s > key.y - key.radius) {
                const double dot = c * (key.x - key.radius) + s * (key.y - key.radius);
                const double cross = c * (key.y - key.radius) - s * (key.x - key.radius);
                t = dot + std::sqrt(std::max(0., double(key.radius) * key.radius - cross * cross));
            }
            const double x = t * c0, y = t * s0, c2 = std::cos(2 * angle), s2 = std::sin(2 * angle);
            double cn = c0, sn = s0;
            for (int n = 0; n < modes; n++) {
                sums[n * 2] += x * cn * 2 / boundarySamples;
                sums[n * 2 + 1] += y * sn * 2 / boundarySamples;
                const double next = cn * c2 - sn * s2;
                sn = sn * c2 + cn * s2;
                cn = next;
            }
        }
        std::copy(sums.begin(), sums.end(), coefficients.begin());

        constexpr int rings = 144, sectors = 128;
        static_assert((2 * sectors + 65 + 129) * rings + 1 < 65536);
        std::vector<double> angles{0, std::numbers::pi * .5};
        for (int i = 1; i < sectors; i++) {
            const double a = double(i) / sectors * std::numbers::pi * .5;
            angles.push_back(a);
            // Additional samples around narrow capsule corners; no changing
            // geometry, just a better distribution of the cache tessellation.
            angles.push_back(std::atan2(key.y * std::sin(a), key.x * std::cos(a)));
        }
        // The exact Fourier tail retains the boundary's tiny circular corner.
        // Resolve that arc explicitly rather than spending more vertices on
        // the entire dome, especially for the approved 1–2 px radius cases.
        for (int i = 0; i <= 64; i++) {
            const double a = double(i) / 64 * std::numbers::pi * .5;
            angles.push_back(std::atan2(key.y - key.radius + key.radius * std::sin(a),
                                        key.x - key.radius + key.radius * std::cos(a)));
        }
        // Resolve the Fourier tail on BOTH sides of the corner, not just its
        // circular arc. Otherwise a subpixel bend can fall between the arc
        // endpoint and the next uniform angular sample.
        const double cornerAngle = std::atan2(key.y, key.x);
        for (int i = 0; i <= 128; i++)
            angles.push_back(std::clamp(cornerAngle + .16 * (double(i) / 128 - .5), 0., std::numbers::pi * .5));
        std::sort(angles.begin(), angles.end());
        angles.erase(
            std::unique(angles.begin(), angles.end(), [](double a, double b) { return std::abs(a - b) < 1e-12; }),
            angles.end());
        const int stride = angles.size();
        std::vector<float> data{0, 1, 0};
        std::vector<uint16_t> index;
        for (int ring = 1; ring <= rings; ring++) {
            const float t = 1.F - float(ring) / rings, rho = 1 - t * t;
            for (const auto angle : angles) {
                data.push_back(rho);
                data.push_back(std::cos(angle));
                data.push_back(std::sin(angle));
            }
        }
        for (int angle = 0; angle < stride - 1; angle++) {
            index.insert(index.end(), {0, uint16_t(1 + angle), uint16_t(2 + angle)});
            for (int ring = 1; ring < rings; ring++) {
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
    void bind(GLuint program) const {
        glUniform2fv(glGetUniformLocation(program, "coefficients"), modes, coefficients.data());
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
} // namespace CushionField
