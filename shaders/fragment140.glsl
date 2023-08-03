#version 140

uniform sampler2D color_tex;
uniform sampler2D light_tex;
uniform vec2 tex_size;
uniform sampler2D background_tex;

in vec2 v_tex_coords;

out vec4 f_color;


float saturate(float x) { return clamp(x, 0., 1.); }

vec2 saturate(vec2 x) { return clamp(x, vec2(0), vec2(0)); }

vec3 saturate(vec3 x) { return clamp(x, vec3(0), vec3(1)); }



float weight(float t, float log2radius, float gamma) {
    return exp(-gamma * pow(log2radius - t, 2.));
}

vec4 sampleBlurred(sampler2D tex, vec2 uv, float radius, float gamma) {
    float lod = log2(radius);
    vec4 blurredColor = vec4(0.0);
    float weightSum = 0.0;

    // Perform a weighted sum across neighboring mipmap levels
    for (float i = lod - 1.0; i <= lod + 1.0; i += 1.0) {
        float w = weight(i, lod, gamma);
        blurredColor += textureLod(tex, uv, i) * w;
        weightSum += w;
    }

    return blurredColor / weightSum;
}

// Pixel Art Filtering by Klems
// https://www.shadertoy.com/view/MllBWf
vec2 getCoordsAA(vec2 uv)
{
    float w = 1.0; // 1.5
    vec2 fl = floor(uv + 0.5);
    vec2 fr = fract(uv + 0.5);
    vec2 aa = fwidth(uv) * w * 0.5;
    fr = smoothstep(0.5 - aa, 0.5 + aa, fr);
    
    return fl + fr - 0.5;
}

vec4 sampleTexAA(sampler2D ch, vec2 uv)
{
    return texture(ch, getCoordsAA(uv));
}


void main() {
    vec4 col = texture(color_tex, v_tex_coords, 0.0);
    //vec3 light = texture(light_tex, v_tex_coords).rgb;
    vec4 light = texture(light_tex, v_tex_coords);
    
    // Occlude ambient color but subtract light
    
    //float pixelate = sqrt(tex_size.x*tex_size.y);
    float pixelate = tex_size.x / 2;
    float d = 1.0 / pixelate;
	float ar = tex_size.x / tex_size.y;
    vec2 pixelated_uv = floor(v_tex_coords / d) * d;

    vec3 occ = 1.0 - vec3(sampleBlurred(color_tex, pixelated_uv, 2.0, 0.5).a);
    vec3 occ2 = 1.0 - vec3(sampleBlurred(color_tex, pixelated_uv, 16.0, 0.35).a);
    vec3 occ3 = 1.0 - vec3(sampleBlurred(color_tex, pixelated_uv, 32.0, 0.2).a);
    occ += occ2 * 0.4 + occ3 * 0.25;
    occ = clamp(occ, vec3(0.0), vec3(1.0));

    float ambientCol = 0.01;
    vec3 ambient = vec3(0.5, 0.5, 0.5) * (1.0 - pixelated_uv.y);

    
    
    col.rgb *= ambientCol + occ * (1.0 - ambientCol);
    col.rgb = clamp(col.rgb, vec3(0), vec3(1));
    // if (col.rgb == vec3(0.0)) {
    //     col.rgb = light;
    // } else {
    //     col.rgb = min(col.rgb + light, vec3(1.0));
    // }

    vec4 bg_col = texture(background_tex, vec2(v_tex_coords.x, 1.0 - v_tex_coords.y));
    vec4 final_col = mix(bg_col, col, col.a);

    f_color = final_col;
    //f_color = vec4(vec3(occ), 1.0);
    //f_color = light;
    //f_color = vec4(ambient, 1.0);
    //f_color = textureLod(tex, v_tex_coords, 2.0);
}