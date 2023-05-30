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

    if (self.mat == EMPTY) {
        emptyStep(self, moveRight);
    } else if (isMovSolid(self)) {
        ivec2 res = movSolidStep(self, moveRight, true);
        if (res == pos) {
            setCell(pos, self, true);
        } else {
            pullCell(res, pos);
        };
    } else if (isLiquid(self)) {
        ivec2 res = liquidStep(self, moveRight, true);
        if (res == pos) {
            setCell(pos, self, true);
        } else {
            pullCell(res, pos);
        };
    } else if (isSolid(self)) {
        setCell(pos, self, true);
    } else if (isGas(self)) {
        ivec2 res = gasStep(self, moveRight, true);
        if (res == pos) {
            setCell(pos, self, true);
        } else {
            pullCell(res, pos);
        };
    }
}

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= simSize.x || pos.x < 0 || pos.y >= simSize.y || pos.y < 0) {
        return;
    };

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
        //imageStore(output_light, pos, vec4(getMaterialFromID(brushMaterial).emission, 1.0));
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

    vec2 p = vec2(pos) / vec2(simSize);
    //imageStore(output_color, pos, vec4(p.x, p.y, 0.0, 1.0));
}
