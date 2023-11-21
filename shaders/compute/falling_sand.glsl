#version 430
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

#define SCREEN_IS_BORDER
#define EMPTY_MAX_DISPERSION_CHECK 8
#define USE_CIRCLE_BRUSH
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
//#include "materials.glsl"
#include "gen/materials.glsl"
//#include "material_helpers.glsl"

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

layout(r32i) uniform iimage2D collision_data;

layout(binding = 4) uniform sampler2D input_light;
layout(rgba32f, binding = 5) uniform writeonly image2D output_light;
layout(rgba32f, binding = 6) uniform writeonly image2D output_effects;
layout(r32ui, binding = 7) uniform volatile coherent uimage2D image_lock;

layout(std430, binding = 8) volatile buffer RBCells {
    RBCell rb_cells[];
};

struct RigidBody {
    int id;
    vec2 pos;
    float rot;
};

uniform RigidBodies {
    RigidBody bodies[16];
};

Cell[8] neighbours;

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
    vec4 rand1 = hash43(uvec3(pos_rounded, frame));
    vec4 rand2 = hash43(uvec3(pos_rounded, frame/8));

    bool shouldMirror = rand1.x < 0.5;
    if (shouldMirror) {
        swap(self, right);
        swap(down, downright);
    }


    applyMirroredRules(self, right, down, downright, pos_rounded);
    // float ownDensity = self.mat.density;

    // // The lower, the less likely it will be to fall diagonally, forming higher piles
    // // TODO: Make this a material property
    // float downspread = 0.7;

    // // First process movable solids and if that fails, process liquid movements
    // if (shouldDoMovSolidStep(self)) {
    //     if (down.mat.density < ownDensity) {
    //         swap(self, down);
    //     } else if (right.mat.density < ownDensity && downright.mat.density < ownDensity) {
    //         if (rand1.z < downspread) swap(self, downright);
    //     //  We couldnt move using movSolidStep, so now try liquid movement
    //     } else if (shouldDoLiquidStep(self)) {
    //         if (right.mat.density < ownDensity) {
    //             swap(self, right);
    //         }
    //     }
    // }
    
    // if (shouldDoGasStep(down)) {
    //     float gasDissolveChance = 0.01;
    //     if (rand1.y < gasDissolveChance) {
    //         down = newCell(EMPTY, pos_rounded);
    //     } else {
    //         if (!isSolid(self) && down.mat.density < self.mat.density) {
    //             swap(down, self);
    //         } else if (!isSolid(right) && down.mat.density < right.mat.density) {
    //             swap(down, right);
    //         }
    //     }
    // } else if (shouldDoLiquidStep(down)) {
    //     if (downright.mat.density < down.mat.density) {
    //         swap(down, downright);
    //     }
    // }


    // if (isEmpty(self)) {
    //     if (isPlant(down)) {
    //         if (rand1.x < 0.0001) self = newCell(VINE, pos_rounded);
    //     } else if (down.mat == SAND && downright.mat == WATER) {
    //         if (rand1.x < 0.01) self = newCell(VINE, pos_rounded);
    //     }
    // }

    // if (isPlant(self) && isEmpty(down) && isEmpty(right) && isEmpty(downright)) {
    //     self = newCell(EMPTY, pos_rounded);
    //     down = newCell(VINE, pos_rounded);
    // }


    if (shouldMirror) {
        swap(self, right);
        swap(down, downright);
    }

    if (!shouldMirror) {
        applyRightRules(self, right, down, downright, pos_rounded);
    } else {
        applyLeftRules(self, right, down, downright, pos_rounded);
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

    if (time < 0.1) {
        setCell(pos, MAT_EMPTY);
    }


    
    uint rb_cell_idx = gl_GlobalInvocationID.x;
    if (rb_cell_idx >= 0 && rb_cell_idx < rb_cells.length()) {
        RBCell cell = rb_cells[rb_cell_idx];
        cell.prev_pos = cell.pos;

        // If the Rigidbody index is valid, proceed
        if (cell.rb_idx >= 0 && cell.rb_idx < bodies.length()) {
            RigidBody rb = bodies[cell.rb_idx];
            float rot = rb.rot;
            ivec2 body_pos = ivec2(rb.pos);
            vec2 p = vec2(cell.orig_off);
            // Position in body-local coordinates
            vec2 p_local = p;
            // Rotated position in body-local coords
            vec2 p_rot = rotatePoint(p_local, rot);
            // New position in global coords
            ivec2 rot_glob_pos = body_pos + ivec2(round(p_rot));

            // Get the cell that was previously at the cells position, might be the RBCell itself
            Cell prev_cell = getCell(cell.prev_pos);
            Material rb_mat = getMaterialFromID(cell.matID);
            
            int black = 0;
            int red = int(rb_cell_idx);
            // Check if we wrote the value, if not, check surrounding pixels
            if (imageAtomicCompSwap(collision_data, rot_glob_pos, black, red) == black) {
                ivec2[8] DIRECTIONS = {UP, DOWN, LEFT, RIGHT, UPRIGHT, DOWNLEFT, UPLEFT, DOWNRIGHT};

                for (int i = 0; i < DIRECTIONS.length(); i++) {
                    ivec2 dir = DIRECTIONS[i];
                    // Displaced position of the cell
                    ivec2 disp_pos = rot_glob_pos + dir;
                    if (imageAtomicCompSwap(collision_data, disp_pos, black, red) != black) {
                        if (time < 0.1 || prev_cell.mat != rb_mat) {
                            setCell(disp_pos, rb_mat);
                        } else {
                            // Get the cell from the previous iteration
                            setCell(disp_pos, prev_cell);//getCell(cell.pos)
                        }
                        cell.pos = disp_pos;
                        break;
                    }
                }
            } else {
                if (time < 0.1 || prev_cell.mat != rb_mat) {
                    setCell(rot_glob_pos, rb_mat);
                } else {
                    setCell(rot_glob_pos, prev_cell);//rb_mat
                }
                cell.pos = rot_glob_pos;
            };
            rb_cells[rb_cell_idx] = cell;
            
            barrier(); // Here, all threads/ workers should have (dis-)placed their cells
            // If some RBCell moved out of this position, clear the cell
            if (prev_cell.mat != MAT_EMPTY && imageLoad(collision_data, cell.prev_pos).r == 0) {
                setCell(cell.prev_pos, MAT_EMPTY);
                return;
            };
        }
    };
    
    // barrier();

    // int rb_idx = imageLoad(collision_data, pos).r;
    // if (rb_idx != 0) {
    //     RBCell cell = rb_cells[rb_idx];
    //     // imageStore(output_color, cell.prev_pos, vec4(0.0, 0.0, 1.0, 1.0));
    //     // imageStore(output_color, cell.pos, vec4(1.0, 0.0, 0.0, 1.0));
    // } else {
    //     //setCell(pos, MAT_EMPTY);
    //     //imageStore(output_color, pos, vec4(0.0, 0.0, 0.0, 1.0));
    // };
    // imageStore(output_color, pos, vec4(float(rb_idx), 0.0, 0.0, 1.0));

    return;


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
        setCell(pos, getMaterialFromID(brushMaterial));
        return;
    };


    Cell result = simulate();
    setCell(pos, result);


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
