#version 140

in vec2 position;
uniform vec2 texSize;

void main() {
    vec2 pos_scaled = position / texSize;
    vec2 pos = vec2((pos_scaled.x - 0.5) * 2.0, 0.0 - ((pos_scaled.y - 0.5) * 2.0));
    gl_Position = vec4(pos, 0.0, 1.0);
}