#version 300 es
precision highp float;
uniform highp sampler2D seeds;
uniform vec2 maskSize;
uniform float jump;
in vec2 uv;
out vec4 color;
void main() {
    vec4 best = texture(seeds, uv);
    float closest = best.b > 0.5 ? dot(best.rg, best.rg) : 1e9;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            vec2 delta = vec2(x, y) * jump;
            vec2 p = uv + delta / maskSize;
            if (any(lessThan(p, vec2(0.0))) || any(greaterThan(p, vec2(1.0)))) continue;
            vec4 candidate = texture(seeds, p);
            vec2 offset = candidate.rg + delta;
            float d = dot(offset, offset);
            if (candidate.b > 0.5 && d < closest) {
                closest = d;
                best.rgb = vec3(offset, 1.0);
            }
        }
    }
    color = best;
}
