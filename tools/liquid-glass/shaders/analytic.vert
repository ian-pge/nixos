#version 300 es
precision highp float;
uniform vec2 resolution;
uniform vec4 shapes[64];
uniform float radii[64];
out vec2 uv;
flat out vec4 shapeRect;
flat out float cornerRadius;
flat out int profileIndex;
void main() {
    const vec2 corners[6] = vec2[6](vec2(0,0), vec2(1,0), vec2(0,1), vec2(0,1), vec2(1,0), vec2(1,1));
    shapeRect = shapes[gl_InstanceID];
    profileIndex = gl_InstanceID;
    cornerRadius = radii[gl_InstanceID];
    vec2 p = shapeRect.xy - 2.0 + corners[gl_VertexID] * (shapeRect.zw + 4.0);
    uv = p / resolution;
    gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
}
