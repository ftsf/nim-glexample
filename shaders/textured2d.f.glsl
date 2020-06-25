#version 330 core
out vec4 FragColor;
in  vec2 TexCoords;

uniform sampler2D tex;
uniform vec4 objectColor;
uniform vec4 layerColor;

void main()
{
    FragColor = texture(tex, TexCoords) * objectColor * layerColor;
}
