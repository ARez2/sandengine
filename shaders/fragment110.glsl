#version 110

uniform sampler2D color_tex;
uniform sampler2D light_tex;
uniform vec2 tex_size;

varying vec2 v_tex_coords;

void main() {
    vec4 col = texture2D(color_tex, v_tex_coords, 0.0);
    gl_FragColor = col;
}