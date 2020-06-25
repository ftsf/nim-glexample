#version 330 core
layout (location = 0) in vec4 posUV;

out vec2 TexCoords;

uniform mat4x4 projection;
uniform mat4x4 view;
uniform mat4x4 model;

void main() {
    gl_Position = projection * view * model * vec4(posUV.xy, 0, 1);
    TexCoords = posUV.zw;
}
