#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float strength;
};

layout(binding = 1) uniform sampler2D source;

void main()
{
    vec2 uv = qt_TexCoord0 - vec2(0.5);
    float r = length(uv);
    float a = atan(uv.y, uv.x);
    // Swirl strongest at the centre, fading outward, breathing in and out.
    a += strength * exp(-r * 2.1) * sin(time * 0.35);
    vec2 p = vec2(cos(a), sin(a)) * r * 0.90 + vec2(0.5);
    fragColor = texture(source, p) * qt_Opacity;
}
