#pragma once
#include <GLES3/gl3.h>
#include <algorithm>
#include <bit>
#include <stdexcept>
#include <vector>

// Geometry-independent quarter-field cache, shared by current and archived models.
// All methods require a current GL context. The caller restores compositor state.
namespace ProfileField {
struct Key {
    float x = 0, y = 0, radius = 0, floor = 0;
    bool operator==(const Key&) const = default;
};
struct Atlas {
    GLuint texture = 0, fb = 0;
    int size = 0, capacity = 0;
    std::vector<Key> keys;
    std::vector<bool> valid;
    void release() {
        if (texture)
            glDeleteTextures(1, &texture);
        if (fb)
            glDeleteFramebuffers(1, &fb);
        texture = fb = 0;
        size = capacity = 0;
        keys.clear();
        valid.clear();
    }
    void allocate(int resolution, int layers) {
        const int count = std::min(64U, std::bit_ceil(unsigned(std::max(1, layers))));
        if (texture && size == resolution && capacity >= count)
            return;
        release();
        size = resolution;
        capacity = count;
        glGenTextures(1, &texture);
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D_ARRAY, texture);
        glTexStorage3D(GL_TEXTURE_2D_ARRAY, 1, GL_RGBA16F, size, size, capacity);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glGenFramebuffers(1, &fb);
        keys.resize(capacity);
        valid.resize(capacity, false);
    }
    template <class Mesh> bool update(int layer, Key key, GLuint program, Mesh& mesh) {
        if (layer < 0 || layer >= capacity)
            throw std::runtime_error("pebble field layer out of bounds");
        if (valid[layer] && keys[layer] == key)
            return false;
        mesh.init(key);
        glBindFramebuffer(GL_FRAMEBUFFER, fb);
        glFramebufferTextureLayer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, texture, 0, layer);
        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
            throw std::runtime_error("incomplete pebble field framebuffer");
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);
        glUseProgram(program);
        if constexpr (requires { mesh.bind(program); })
            mesh.bind(program);
        glUniform4f(glGetUniformLocation(program, "profile"), key.x, key.y, key.radius, key.floor);
        glBindVertexArray(mesh.vao);
        glDrawElements(GL_TRIANGLES, mesh.count, GL_UNSIGNED_SHORT, nullptr);
        keys[layer] = key;
        valid[layer] = true;
        return true;
    }
};
} // namespace ProfileField
