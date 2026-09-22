#version 300 es
precision highp float;
uniform sampler2D content;
uniform vec2 maskSize;
uniform vec4 contentRect;
in vec2 uv;
out vec4 color;
void main() {
    const float threshold = 0.035;
    float a = texture(content, contentRect.xy + uv * contentRect.zw).a;
    bool here = a > threshold;
    float closest = 1e9;
    vec2 offset = vec2(0.0);
    // Interpolate crossings of the antialiased silhouette instead of snapping
    // the contour to pixel centers. Store LOCAL pixel offsets: half-float UVs
    // lose several pixels of precision towards the right of a 5K display.
    for (int y = -1; y <= 1; ++y) for (int x = -1; x <= 1; ++x) {
        if (x == 0 && y == 0) continue;
        vec2 step = vec2(x, y);
        vec2 at = clamp(uv + step / maskSize, vec2(0.0), vec2(1.0));
        float b = texture(content, contentRect.xy + at * contentRect.zw).a;
        if ((b > threshold) == here) continue;
        vec2 crossing = step * clamp((threshold - a) / (b - a), 0.0, 1.0);
        float d = dot(crossing, crossing);
        if (d < closest) { closest = d; offset = crossing; }
    }
    color = vec4(offset, closest < 1e8 ? 1.0 : 0.0, float(here));
}
