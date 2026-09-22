#version 300 es
precision highp float;
uniform sampler2D background;
uniform sampler2D content;
uniform vec2 resolution;
uniform vec4 contentRect;
flat in vec4 shapeRect;
flat in float cornerRadius;
uniform float scale;
in vec2 uv;
out vec4 color;

const float IOR = 1.50;
const float ABSORPTION = 1.40;

vec3 sampleGlass(vec2 at, vec2 inward, float dispersion) {
    // Keep the existing fixed five-tap filter. No angle-dependent blur.
    vec2 stepUV = 1.62635 * scale / resolution;
    vec2 along = inward * stepUV;
    vec2 across = vec2(-inward.y, inward.x) * stepUV;
    vec3 a = texture(background, at + along).rgb;
    vec3 b = texture(background, at - along).rgb;
    vec3 c = texture(background, at + across).rgb;
    vec3 e = texture(background, at - across).rgb;
    vec3 ambient = (a + b + c + e) * 0.25;
    vec3 result = (texture(background, at).rgb + ambient) * 0.5;
    result.r += dispersion * (a.r - b.r);
    result.b -= dispersion * (a.b - b.b);
    return result;
}

void main() {
    vec4 front = texture(content, contentRect.xy + uv * contentRect.zw);
    if (front.a < 0.002) { color = vec4(texture(background, uv).rgb, 1.0); return; }
    if (front.a == 1.0) { color = front; return; }
    vec2 halfSize = max(shapeRect.zw / (2.0 * scale), vec2(0.01));
    vec2 p = (uv * resolution - shapeRect.xy - shapeRect.zw * 0.5) / scale;
    float radius = clamp(cornerRadius / scale, 0.0, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + radius;
    vec2 outside = max(q, vec2(0.0));
    float outsideLength = length(outside);
    float signedDistance = radius - outsideLength - min(max(q.x, q.y), 0.0);
    vec2 outward = outsideLength > 0.00001 ? sign(p) * outside / outsideLength
        : (q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y)));
    vec2 gradDistance = -outward;
    float d = max(signedDistance, 0.0);

    // One continuous height field drives the refraction and smoked thickness.
    // A broad paraboloid gives a gentle body curve; the circular meniscus joins
    // it with zero slope at its inner edge. Small pills keep a narrow meniscus.
    float shortest = min(halfSize.x, halfSize.y);
    vec2 bodyRadius = 48.0 + 2.0 * (halfSize - shortest);
    vec2 bodyScale = 0.5 / bodyRadius;
    float centreHeight = 8.0 + dot(halfSize * halfSize, bodyScale);
    float bodyHeight = max(centreHeight - dot(p * p, bodyScale), 0.0);
    vec2 bodySlope = -p / bodyRadius;
    // End the meniscus before the SDF's inner medial axis: its vanishing
    // derivative then prevents a diagonal normal crease in rounded corners.
    float bevelWidth = max(min(min(20.0, shortest * 0.45), max(radius, 0.5)), 0.5);
    float t = clamp(d / bevelWidth, 0.0, 1.0);
    float arc = sqrt(0.04 + t * (2.0 - t));
    const float arcRange = 0.819803903;
    float bevel = (arc - 0.2) / arcRange;
    float bevelSlope = (1.0 - t) / (bevelWidth * arc * arcRange);
    vec2 slope = bodySlope * bevel + bodyHeight * bevelSlope * gradDistance;
    vec3 normal = normalize(vec3(-slope, 1.0));
    vec2 inward = length(slope) > 0.00001 ? normalize(slope) : vec2(0.0, 1.0);
    // Screen-space thin-lens displacement, bounded by the existing 40 px halo.
    vec2 bend = -normal.xy * (36.0 * (2.0 * (IOR - 1.0)) * scale);
    vec2 at = clamp(uv + bend / resolution, vec2(0.0), vec2(1.0));
    float edge = 1.0 - t;
    vec3 glass = sampleGlass(at, inward, 0.0375 * edge * edge);
    float thickness = 0.70 + 0.30 * clamp(bodyHeight * bevel / centreHeight, 0.0, 1.0);
    float transmission = exp(-ABSORPTION * thickness);
    glass = mix(vec3(0.028, 0.034, 0.045), glass, transmission);

    // No synthetic reflection or rear-edge accent: curvature bends the
    // background without adding either a white outline or a dark frame.
    float coverage = smoothstep(0.005, 0.12, front.a);
    vec3 original = texture(background, uv).rgb;
    color = vec4(front.rgb + mix(original, glass, coverage) * (1.0 - front.a), 1.0);
}
