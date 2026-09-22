#version 300 es
precision highp float;
uniform highp sampler2D field;
uniform vec2 direction;
in vec2 uv;
out vec4 color;
void main() {
    // A small separable Gaussian on the signed distance only, never on the
    // widget coverage or text. Stabilizes normals without blurring the outline.
    vec2 step = direction / vec2(textureSize(field, 0));
    float d = texture(field, uv).r * 0.375;
    d += (texture(field, uv + step).r + texture(field, uv - step).r) * 0.25;
    d += (texture(field, uv + 2.0*step).r + texture(field, uv - 2.0*step).r) * 0.0625;
    color = vec4(d, 0.0, 0.0, 1.0);
}
