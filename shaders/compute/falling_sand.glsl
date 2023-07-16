#version 450
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

#define SCREEN_IS_BORDER
#define EMPTY_MAX_DISPERSION_CHECK 8
#define USE_CIRCLE_BRUSH
//#define DEBUG_SHOW_UPDATERECT
//#define DEBUG_SHOW_ORIG_POS
//#define DEBUG_SHOW_MOVERIGHT

#include "directions.glsl"
#include "math.glsl"
#include "materials.glsl"
#include "cell.glsl"
#include "material_helpers.glsl"

uniform sampler2D input_data;
layout(rgba32f) uniform writeonly image2D output_data;
layout(rgba32f) uniform writeonly image2D output_color;
// uniform Params {
// } params 
uniform bool moveRight;
uniform vec2 mousePos;
uniform uint brushSize;
uniform int brushMaterial;
uniform float time;
uniform ivec2 simSize;
uniform int frame;

layout(rgba32f) uniform image2D collision_data;

layout(binding = 4) uniform sampler2D input_light;
layout(rgba32f, binding = 5) uniform writeonly image2D output_light;
layout(rgba32f, binding = 6) uniform writeonly image2D output_effects;
layout(r32ui, binding = 7) uniform volatile coherent uimage2D image_lock;

Cell[8] neighbours;

#include "operations.glsl"


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

    if (self.mat == EMPTY && right.mat == EMPTY && down.mat == EMPTY && downright.mat == EMPTY) {
        return Cell(EMPTY, pos_rounded, pos_rounded);
    }

    Cell up = getCell(pos_rounded + UP);
    Cell upright = getCell(pos_rounded + UPRIGHT);
    vec4 v = hash43(uvec3(pos_rounded, frame));
    vec4 v2 = hash43(uvec3(pos_rounded, frame/8));

    if (v.x < 0.5) {
        swap(self, right);
        swap(down, downright);
    }



    float ownDensity = self.mat.density;

    // The lower, the less likely it will be to fall diagonally, forming higher piles
    // TODO: Make this a material property
    float downspread = 0.7;

    // First process movable solids and if that fails, process liquid movements
    if (shouldDoMovSolidStep(self)) {
        if (down.mat.density < ownDensity) {
            swap(self, down);
        } else if (right.mat.density < ownDensity && downright.mat.density < ownDensity) {
            if (v.z < downspread) swap(self, downright);
        //  We couldnt move using movSolidStep, so now try liquid movement
        } else if (shouldDoLiquidStep(self)) {
            if (right.mat.density < ownDensity) {
                swap(self, right);
            }
        }
    } else if (shouldDoGasStep(down)) {
        float gasDissolveChance = 0.01;
        if (v.y < gasDissolveChance) {
            down = Cell(EMPTY, pos_rounded, pos_rounded);
        } else {
            if (!isSolid(self) && down.mat.density < self.mat.density) {
                swap(down, self);
            } else if (!isSolid(right) && down.mat.density < right.mat.density) {
                swap(down, right);
            }
        }
    }



    if (v.x < 0.5) {
        swap(self, right);
        swap(down, downright);
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

    return Cell(EMPTY, pos, pos);
}



void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= simSize.x || pos.x < 0 || pos.y >= simSize.y || pos.y < 0) {
        return;
    };

    // TODO: Smaller init time
    if (time < 0.1) {
        setCell(pos, EMPTY, false);
    }


    // Process input
    vec2 mousepos = mousePos * vec2(simSize);
    vec2 diffMouse = abs(vec2(mousepos - pos));
    bool applyBrush = false;
    #ifdef USE_CIRCLE_BRUSH
    float mouseDist = sqrt(pow(diffMouse.x, 2) + pow(diffMouse.y, 2));
    applyBrush = brushSize > 0 && mouseDist <= float(brushSize) / 2.0;
    #else
    applyBrush = brushSize > 0 && diffMouse.x <= brushSize && diffMouse.y <= float(brushSize) / 2.0;
    #endif // USE_CIRCLE_BRUSH
    
    if (applyBrush) {
        setCell(pos, getMaterialFromID(brushMaterial), false);
        return;
    };


    Cell result = simulate();
    setCell(pos, result, false);


    // ivec2[8] neighPositions = getDiagonalNeighbours(pos);
    // for (int n = 0; n < neighbours.length(); n++) {
    //     neighbours[n] = getCell(neighPositions[n]);
    // }

    

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
