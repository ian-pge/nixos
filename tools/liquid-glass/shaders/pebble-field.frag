#version 300 es
precision highp float;
in vec4 profileData;
out vec4 color;
void main() {
    color = vec4(normalize(profileData.xyz), clamp(profileData.w,0.0,1.0));
}
