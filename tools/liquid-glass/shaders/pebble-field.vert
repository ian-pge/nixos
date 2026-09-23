#version 300 es
precision highp float;
// Port of viewer/src/pebble.ts. Only the normalized quarter profile is cached;
// position, uniform bounce scale and optical height are applied when sampling.
layout(location = 0) in vec3 parameter; // level u, outward contour normal XY
uniform vec4 profile; // normalized half-width/height, radius, 0.25 / shortest
out vec4 profileData; // normalized geometric normal, normalized height

struct Contour { vec2 halfSize; float radius; float rounding; };
float smoother(float t) { return t*t*t*(10.0+t*(-15.0+6.0*t)); }
Contour contourAt(float level) {
    float u = clamp(level, 0.0, 1.0);
    float radius = clamp(profile.z, 0.0, 1.0);
    float start = min(radius * 0.4, 0.12);
    if (u <= start) return Contour(profile.xy - u, radius - u, 0.0);
    float v = (u - start) / (1.0 - start);
    float blend = clamp(smoother(v), 0.0, 1.0);
    vec2 halfSize = vec2(1.0 - u) + (profile.xy - 1.0) * (1.0 - blend);
    float remaining = radius - start;
    float t = (u - start) / max(max(remaining, profile.w), 1e-7);
    float softRadius = remaining / (1.0 + t + t*t);
    float r = clamp((1.0-blend)*(1.0-blend)*softRadius + blend*min(halfSize.x, halfSize.y),
        0.0, min(halfSize.x, halfSize.y));
    vec2 axes = max(halfSize - r, vec2(0.0));
    float ratio = max(axes.x, axes.y) > 0.0 ? min(axes.x, axes.y) / max(axes.x, axes.y) : 0.0;
    float desired = 0.45 * blend;
    float rounding = ratio > 0.0 && desired > 0.0 ? desired * ratio / (desired + ratio) : 0.0;
    // Below this threshold the positional difference is subpixel, and the
    // exact rounded rectangle avoids underflow in single-precision ellipses.
    if (rounding < 1e-6) rounding = 0.0;
    return Contour(halfSize, r, rounding);
}
vec2 ellipseAxes(Contour c) {
    vec2 p = c.halfSize - c.radius;
    return max((p - c.rounding * p.yx) / (1.0-c.rounding*c.rounding), vec2(0.0));
}
float supportAt(Contour c, vec2 n) {
    if (c.rounding == 0.0) return dot(c.halfSize - c.radius, abs(n)) + c.radius;
    vec2 a = ellipseAxes(c);
    float e2 = c.rounding*c.rounding;
    return a.x * sqrt(n.x*n.x+e2*n.y*n.y) + a.y * sqrt(n.y*n.y+e2*n.x*n.x) + c.radius;
}
void main() {
    float u = parameter.x;
    if (u >= 1.0) {
        gl_Position = vec4(-1.0,-1.0,0.0,1.0);
        profileData = vec4(0.0,0.0,1.0,1.0);
        return;
    }
    vec2 outward = normalize(parameter.yz);
    Contour c = contourAt(u);
    float e = max(c.rounding,1e-6), e2=e*e;
    vec2 axes=max(((c.halfSize-c.radius)-e*(c.halfSize.yx-c.radius))/(1.0-e2),vec2(0));
    float a=inversesqrt(outward.x*outward.x+e2*outward.y*outward.y);
    float b=inversesqrt(outward.y*outward.y+e2*outward.x*outward.x);
    vec2 p=axes.x*vec2(outward.x,e2*outward.y)*a
        +axes.y*vec2(e2*outward.x,outward.y)*b+c.radius*outward;
    if(outward.y==0.0)p=vec2(c.halfSize.x,0);
    if(outward.x==0.0)p=vec2(0,c.halfSize.y);
    float height = sqrt(max(0.0, u*(2.0-u)));
    vec3 normal;
    if (u <= 0.0) normal = vec3(outward,0.0);
    else {
        float delta = min(0.001, min(u,1.0-u)*0.25);
        float inwardSpeed = (supportAt(contourAt(u-delta),outward)-supportAt(contourAt(u+delta),outward))/(2.0*delta);
        float rise = (1.0-u)/max(height,1e-7);
        normal = normalize(vec3(outward*rise, max(inwardSpeed,1e-7)));
    }
    profileData = vec4(normal,height);
    gl_Position = vec4(p/profile.xy*2.0-1.0,0.0,1.0);
}
