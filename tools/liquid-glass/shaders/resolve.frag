#version 300 es
precision highp float;
uniform highp sampler2D seeds;
uniform sampler2D content;
uniform vec2 resolution;
uniform vec4 contentRect;
in vec2 uv;
out vec4 color;
void main() {
    vec4 nearest = texture(seeds, uv);
    vec2 pixelSize = resolution / vec2(textureSize(seeds, 0));
    float d = nearest.b > 0.5 ? length(nearest.rg * pixelSize) : 1000.0;
    float sign = texture(content, contentRect.xy + uv * contentRect.zw).a > 0.035 ? 1.0 : -1.0;
    color = vec4(d * sign, 0.0, 0.0, 1.0);
}
