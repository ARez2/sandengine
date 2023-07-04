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

layout(rgba32f) uniform image2D collision_data;

layout(binding = 4) uniform sampler2D input_light;
layout(rgba32f, binding = 5) uniform writeonly image2D output_light;
layout(rgba32f, binding = 6) uniform writeonly image2D output_effects;
layout(r32ui, binding = 7) uniform volatile coherent uimage2D image_lock;

Cell[8] neighbours;

#include "operations.glsl"

#include "types/movsolid.glsl"
#include "types/gas.glsl"
#include "types/liquid.glsl"
#include "types/empty.glsl"


// Returns the next position of the cell
void update(ivec2 pos) {
    Cell self = getCell(pos);
    
    if (self.mat == NULL) {
        setCell(pos, self, false);
        return;
    };
    bool moveRight = moveRight;
    ivec2 target_pos = pos;

    if (self.mat == EMPTY) {
        emptyStep(self, moveRight);
    } else if (isMovSolid(self)) {
        target_pos = movSolidStep(self, moveRight, true);
    } else if (isLiquid(self)) {
        target_pos = liquidStep(self, moveRight, true);
    } else if (isGas(self)) {
        target_pos = gasStep(self, moveRight, true);
    }

    if (self.mat != EMPTY) {
        if (target_pos == pos) {
            setCell(pos, self, true);
            imageAtomicExchange(image_lock, pos, 1);
        } else {
            //pullCell(target_pos, pos);
            setCell(pos, EMPTY, false);
            setCell(target_pos, self, false);
            imageAtomicExchange(image_lock, pos, 1);
        }
    }
}

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= simSize.x || pos.x < 0 || pos.y >= simSize.y || pos.y < 0) {
        return;
    };

    // TODO: Smaller init time
    if (time < 0.2) {
        setCell(pos, EMPTY, false);
    }

    ivec2[8] neighPositions = getDiagonalNeighbours(pos);
    for (int n = 0; n < neighbours.length(); n++) {
        neighbours[n] = getCell(neighPositions[n]);
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

    update(pos);

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
