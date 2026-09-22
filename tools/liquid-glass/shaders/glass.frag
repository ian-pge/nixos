#version 300 es
precision highp float;
uniform sampler2D background;
uniform sampler2D content;
uniform highp sampler2D boundaries;
uniform vec2 resolution;
uniform vec4 contentRect;
uniform float scale;
in vec2 uv;
out vec4 color;

// Virtual thin-lens material, not a volumetric/path-traced glass object.
// These constants are folded by the shader compiler; IOR drives bending.
// Thickness is relative, not millimetres.
const float IOR = 1.50;
const float THICKNESS = 1.0;
const float EDGE_THICKNESS = 0.70;
const float ABSORPTION = 1.40;

vec3 softBackground(vec2 p, vec2 inward, float dispersion) {
    // Same five taps and blur variance as before. Reuse the normal-aligned
    // pair for chromatic dispersion instead of issuing two more texture reads.
    vec2 stepUV = 1.62635 * scale / resolution;
    vec2 along = inward * stepUV;
    vec2 across = vec2(-inward.y, inward.x) * stepUV;
    vec3 positive = texture(background, p + along).rgb;
    vec3 negative = texture(background, p - along).rgb;
    vec3 result = (texture(background, p).rgb * 4.0 + positive + negative
        + texture(background, p + across).rgb + texture(background, p - across).rgb) / 8.0;
    result.r += dispersion * (positive.r - negative.r);
    result.b -= dispersion * (positive.b - negative.b);
    return result;
}

void main() {
    vec4 front = texture(content, contentRect.xy + uv * contentRect.zw);
    if (front.a < 0.002) {
        color = vec4(texture(background, uv).rgb, 1.0);
        return;
    }
    if (front.a == 1.0) {
        color = front;
        return;
    }
    float d = max(texture(boundaries, uv).r, 0.0);
    // A single broad, continuous gradient serves the body and the meniscus.
    // Near the boundary this is the original 2.5 px stencil; farther inside it
    // gently cancels opposing slopes, without a second set of four reads.
    float bodyRadius = max(2.5 * scale, 0.85 * d);
    vec2 stepUV = bodyRadius / resolution;
    vec2 gradient = vec2(
        texture(boundaries, uv + vec2(stepUV.x, 0.0)).r - texture(boundaries, uv - vec2(stepUV.x, 0.0)).r,
        texture(boundaries, uv + vec2(0.0, stepUV.y)).r - texture(boundaries, uv - vec2(0.0, stepUV.y)).r)
        / (2.0 * bodyRadius);
    float gradientLength = length(gradient);
    vec2 inward = gradientLength > 0.00001 ? gradient / gradientLength : vec2(0.0, 1.0);
    float coherence = smoothstep(0.1, 0.75, gradientLength);
    float rim = 20.0 * scale;
    float x = clamp(1.0 - d / rim, 0.0, 1.0);
    // Keep the narrow meniscus, and add a broad curved body instead of a flat
    // interior. Its samples stay within this capsule (apart from the small
    // edge stencil), so neighbouring capsules do not bend towards each other.
    float profile = (sqrt(1.06) - sqrt(max(1.06 - x*x, 0.06))) / (sqrt(1.06) - sqrt(0.06));
    // Smooth minimum: match the old limits away from the join, but remove its
    // abrupt change of slope. Keep the unnormalised gradient at the centre.
    float localStrength = 0.75 * bodyRadius;
    float join = max(6.0 * scale - abs(26.0 * scale - localStrength), 0.0);
    float bodyStrength = min(26.0 * scale, localStrength) - join * join / (24.0 * scale);
    float thickness = THICKNESS * mix(EDGE_THICKNESS, 1.0, smoothstep(0.0, 1.0, 1.0 - x));
    vec2 bend = inward * ((36.0 / EDGE_THICKNESS) * scale * profile * coherence)
        + gradient * bodyStrength * (1.0 - profile);
    // Thin-lens approximation: optical power scales with index contrast and
    // virtual thickness. Preserve the familiar strength at the reference IOR.
    bend *= (2.0 * (IOR - 1.0)) * thickness;
    vec2 offset = bend / resolution;
    vec2 at = clamp(uv + offset, vec2(0.0), vec2(1.0));
    vec3 glass = softBackground(at, inward, 0.0375 * x*x * coherence);
    // Beer-Lambert-style attenuation replaces luminance-dependent darkening;
    // the same exponential budget previously belonged to the rim highlight.
    float transmission = exp(-ABSORPTION * thickness);
    glass = mix(vec3(0.028, 0.034, 0.045), glass, transmission);
    // Match the analytic path: no synthetic reflection darkening the edge.
    // Fade the material with the QML surface's coverage; text is composited last
    // in its original position and remains unaffected by the refraction.
    float coverage = smoothstep(0.005, 0.12, front.a);
    vec3 original = texture(background, uv).rgb;
    color = vec4(front.rgb + mix(original, glass, coverage) * (1.0 - front.a), 1.0);
}
