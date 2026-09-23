#version 300 es
precision highp float;
uniform sampler2D source;
uniform vec2 direction;
in vec2 uv;
out vec4 color;

void main() {
    // Separable Gaussian: nine coefficients paired into five bilinear reads.
    // Run horizontally then vertically at half resolution. The sampling step
    // is in monitor pixels, so blur strength stays constant across DPI scales.
    color = texture(source, uv) * 0.2270270270;
    color += texture(source, uv + direction * 1.3846153846) * 0.3162162162;
    color += texture(source, uv - direction * 1.3846153846) * 0.3162162162;
    color += texture(source, uv + direction * 3.2307692308) * 0.0702702703;
    color += texture(source, uv - direction * 3.2307692308) * 0.0702702703;
}
