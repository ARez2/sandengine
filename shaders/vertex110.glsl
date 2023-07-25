#version 110


attribute vec2 position;
attribute vec2 tex_coords;

varying vec2 v_tex_coords;

void main() {
    gl_Position = vec4(position, 0.0, 1.0);
    v_tex_coords = vec2(tex_coords.x, 1.0 - tex_coords.y);
}