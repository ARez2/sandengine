#version 430
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

#define SCREEN_IS_BORDER
#define EMPTY_MAX_DISPERSION_CHECK 8
//#define DEBUG_SHOW_UPDATERECT
//#define DEBUG_SHOW_ORIG_POS
//#define DEBUG_SHOW_MOVERIGHT

#include "directions.glsl"
#include "math.glsl"
struct Material {
    int id;
    vec4 color;
    float density;
    vec4 emission;

    int type;
};
#include "cell.glsl"

#include "gen/materials.glsl"

//#include "material_helpers.glsl"

uniform sampler2D input_data;
layout(rgba32f) uniform writeonly image2D output_data;
layout(rgba32f) uniform writeonly image2D output_color;
// uniform Params {
// } params 
uniform bool moveRight;
uniform float time;
uniform ivec2 simSize;
uniform int frame;

layout(rgba32f) uniform image2D collision_data;

layout(binding = 4) uniform sampler2D input_light;
layout(rgba32f, binding = 5) uniform writeonly image2D output_light;
layout(rgba32f, binding = 6) uniform writeonly image2D output_effects;
layout(r32ui, binding = 7) uniform volatile coherent uimage2D image_lock;

#define MODSHAPE_CIRCLE 0
#define MODSHAPE_SQUARE 1

struct SimModification {
    ivec2 position;
    int mod_shape;
    int mod_size;
    int mod_matID;
};

uniform SimModifications {
    SimModification sim_modifications[256];
};

#include "operations.glsl"
#include "gen/rules.glsl"


Cell simulate() {
    ivec2 pos = ivec2(floor(gl_GlobalInvocationID.xy));
    ivec2 off = getMargolusOffset(frame);
    pos += off;

    ivec2 pos_rounded = (pos / 2) * 2;
    ivec2 pos_remainder = pos & 1;
    int marg_idx = pos_remainder.x + pos_remainder.y * 2;
    pos_rounded -= off;
    pos -= off;

    Cell self = getCell(pos_rounded);
    Cell right = getCell(pos_rounded + RIGHT);
    Cell down = getCell(pos_rounded + DOWN);
    Cell downright = getCell(pos_rounded + DOWNRIGHT);

    if (self.mat == MAT_EMPTY && right.mat == MAT_EMPTY && down.mat == MAT_EMPTY && downright.mat == MAT_EMPTY) {
        return newCell(MAT_EMPTY, pos_rounded);
    }

    Cell up = getCell(pos_rounded + UP);
    Cell upright = getCell(pos_rounded + UPRIGHT);
    vec4 rand = hash43(uvec3(pos_rounded, frame));
    vec4 rand2 = hash43(uvec3(pos_rounded, frame/8));

    bool shouldMirror = rand.x < 0.5;
    if (shouldMirror) {
        swap(self, right);
        swap(down, downright);
    }

    applyMirroredRules(self, right, down, downright, rand, pos_rounded);

    if (shouldMirror) {
        swap(self, right);
        swap(down, downright);
    }

    if (!shouldMirror) {
        applyRightRules(self, right, down, downright, rand, pos_rounded);
    } else {
        applyLeftRules(self, right, down, downright, rand, pos_rounded);
    }

    switch (marg_idx) {
        case 0:
            return self;
        case 1:
            return right;
        case 2:
            return down;
        case 3:
            return downright;
    }

    // Maybe pos
    return newCell(MAT_EMPTY, pos_rounded);
}



void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= simSize.x || pos.x < 0 || pos.y >= simSize.y || pos.y < 0) {
        return;
    };

    if (frame == 1) {
        setCell(pos, MAT_EMPTY);
        return;
    }


    bool got_modified = false;
    Material final_modification_mat = MAT_NULL;
    int count = 0;
    for (int i = 0; i < sim_modifications.length(); i++) {
        SimModification mod = sim_modifications[i];
        if (mod.mod_size == 0) {
            break;
        }
        
        ivec2 diff_pos = abs(mod.position - pos);
        Material mat = getMaterialFromID(mod.mod_matID);
        switch (mod.mod_shape) {
            case MODSHAPE_CIRCLE:
                float dist = sqrt(pow(diff_pos.x, 2) + pow(diff_pos.y, 2));
                if (dist <= mod.mod_size) {
                    got_modified = true;
                    final_modification_mat = mat;
                    count++;
                };
                break;
            case MODSHAPE_SQUARE:
                if (diff_pos.x <= mod.mod_size && diff_pos.y <= mod.mod_size) {
                    got_modified = true;
                    final_modification_mat = mat;
                    count++;
                };
                break;
        }
    };

    // if (count == 2) {
    //     imageStore(output_color, pos, vec4(1.0, 0.0, 0.0, 1.0));
    // } else if (count == 1) {
    //     imageStore(output_color, pos, vec4(0.0, 1.0, 0.0, 1.0));
    // } else if (count > 2) {
    //     imageStore(output_color, pos, vec4(0.0, 0.0, 1.0, 1.0));
    // } else {
    //     imageStore(output_color, pos, vec4(0.0, 0.0, 0.0, 1.0));
    // }

    // return;

    if (got_modified && final_modification_mat != MAT_NULL) {
        setCell(pos, final_modification_mat);
        return;
    }


    Cell result = simulate();
    setCell(pos, result);


    #ifdef DEBUG_SHOW_ORIG_POS
    imageStore(output_color, pos, vec4(vec2(getCell(pos).origPos) / vec2(simSize), 0.0, 1.0));
    #endif // DEBUG_SHOW_ORIG_POS
    
    #ifdef DEBUG_SHOW_MOVERIGHT
    vec3 col = vec3(1.0, 0.0, 0.0);
    if (moveRight) {
        col = vec3(0.0, 1.0, 0.0);
    }
    imageStore(output_color, pos, vec4(col, 1.0));
    #endif // DEBUG_SHOW_MOVERIGHT
}
