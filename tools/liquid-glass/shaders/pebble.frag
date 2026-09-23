#version 300 es
precision highp float;
precision highp int;
uniform sampler2D background;
uniform sampler2D blurredBackground;
uniform highp sampler2DArray pebbleProfiles;
flat in int profileIndex;
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
    // The cached backdrop is already blurred. Keep the small fixed filter
    // for smooth refraction and dispersion; no angle-dependent blur.
    vec2 stepUV = 1.62635 * scale / resolution;
    vec2 along = inward * stepUV;
    vec2 across = vec2(-inward.y, inward.x) * stepUV;
    vec3 a = texture(blurredBackground, at + along).rgb;
    vec3 b = texture(blurredBackground, at - along).rgb;
    vec3 c = texture(blurredBackground, at + across).rgb;
    vec3 e = texture(blurredBackground, at - across).rgb;
    vec3 ambient = (a + b + c + e) * 0.25;
    vec3 result = (texture(blurredBackground, at).rgb + ambient) * 0.5;
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
    float shortest = min(halfSize.x, halfSize.y);
    float radius = clamp(cornerRadius / scale, 0.0, shortest);
    vec2 q = abs(p) - halfSize + radius;
    vec2 outside = max(q, vec2(0.0));
    float len = length(outside);
    float d = max(radius - len - min(max(q.x,q.y),0.0), 0.0);
    vec2 outward = len > 0.00001 ? sign(p)*outside/len
        : (q.x > q.y ? vec2(sign(p.x),0) : vec2(0,sign(p.y)));
    vec2 bodyRadius = 48.0 + 2.0*(halfSize-shortest);
    float centreHeight = 8.0 + dot(halfSize*halfSize, 0.5/bodyRadius);
    float rim = min(radius*0.4, shortest*0.12);
    vec4 field = texture(pebbleProfiles, vec3(clamp(abs(p)/halfSize,0.0,1.0),float(profileIndex)));
    // Preserve exact symmetry at the texture's axes despite clamp-to-edge.
    vec2 axisWeight = min(abs(p)/halfSize*vec2(textureSize(pebbleProfiles,0).xy)*2.0,vec2(1));
    vec3 n = vec3(field.xy*axisWeight*sign(p)*(centreHeight/shortest),field.z);
    vec3 normal = dot(n,n) > 1e-10 ? normalize(n) : vec3(0,0,1);
    float height = field.w;
    if (d < rim) {
        // The approved pebble has an exact parallel, uniform rim. Evaluate this
        // narrow band analytically: no silhouette/AA loss from cached sampling.
        float u = d/shortest;
        height = sqrt(max(0.0,u*(2.0-u)));
        normal = normalize(vec3(outward*centreHeight*(1.0-u), shortest*height));
    }
    vec2 inward = length(normal.xy) > 1e-5 ? -normalize(normal.xy) : vec2(0,1);
    // Optical displacement and sampling halo are unchanged.
    vec2 bend = -normal.xy * (36.0 * (2.0 * (IOR - 1.0)) * scale);
    vec2 at = clamp(uv + bend / resolution, vec2(0.0), vec2(1.0));
    float edge = 1.0 - clamp(d/max(rim,0.5),0.0,1.0);
    vec3 glass = sampleGlass(at, inward, 0.0375 * edge * edge);
    float thickness = 0.70 + 0.30 * clamp(height, 0.0, 1.0);
    float transmission = exp(-ABSORPTION * thickness);
    glass = mix(vec3(0.028, 0.034, 0.045), glass, transmission);

    // No synthetic reflection or rear-edge accent: curvature bends the
    // background without adding either a white outline or a dark frame.
    float coverage = smoothstep(0.005, 0.12, front.a);
    vec3 original = texture(background, uv).rgb;
    color = vec4(front.rgb + mix(original, glass, coverage) * (1.0 - front.a), 1.0);
}
