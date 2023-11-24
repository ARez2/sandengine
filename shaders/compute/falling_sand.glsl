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

    if (frame == 0) {
        setCell(pos, MAT_EMPTY);
        return;
    }


    // Define some constant values, to be used in the collision_data image
    int COL_EMPTY = 0;
    int COL_QD_CLEAR = 1;
    int COL_MIN_RB_IDX = 3;
    // If there was a cell here in a previous iteration, queue it for deletion
    if (imageLoad(collision_data, pos).r >= COL_MIN_RB_IDX) {
        imageAtomicExchange(collision_data, pos, COL_QD_CLEAR);
    };
    barrier();
    
    uint rb_cell_idx = gl_GlobalInvocationID.x;
    // Use the gl_GlobalInvocationID to process each cell from the rb_cells uniform
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
            
            int img_write_idx = int(rb_cell_idx + COL_MIN_RB_IDX);
            // Check if the cell is empty or queued for clearing, set it to be our rb_cell_idx, so that no other cell can use it
            if (imageAtomicCompSwap(collision_data, rot_glob_pos, COL_EMPTY, img_write_idx) == COL_EMPTY
            || imageAtomicCompSwap(collision_data, rot_glob_pos, COL_QD_CLEAR, img_write_idx) == COL_QD_CLEAR) {
                ivec2[8] DIRECTIONS = {UP, DOWN, LEFT, RIGHT, UPRIGHT, DOWNLEFT, UPLEFT, DOWNRIGHT};
                // Try out all neighbouring positions
                for (int i = 0; i < DIRECTIONS.length(); i++) {
                    ivec2 dir = DIRECTIONS[i];
                    // Displaced position of the cell
                    ivec2 disp_pos = rot_glob_pos + dir;
                    
                    // Check if the cell is empty or queued for clearing, set it to be our rb_cell_idx, so that no other cell can use it
                    if (imageAtomicCompSwap(collision_data, disp_pos, COL_EMPTY, img_write_idx) == COL_EMPTY
                    || imageAtomicCompSwap(collision_data, disp_pos, COL_QD_CLEAR, img_write_idx) == COL_QD_CLEAR) {
                        cell.pos = disp_pos;
                        break;
                    };
                }
            } else {
                cell.pos = rot_glob_pos;
            };
            rb_cells[rb_cell_idx] = cell;
        }
    };
    
    barrier(); // Here, all threads/ workers should have (dis-)placed their cells

    int col_img = imageLoad(collision_data, pos).r;
    // If the current position is queued for deletion, set it to Empty
    if (col_img == COL_QD_CLEAR) {
        setCell(pos, MAT_EMPTY);
        imageAtomicExchange(collision_data, pos, COL_EMPTY);
    // If some RBCell wants to go into this position, set it here
    } else if (col_img >= COL_MIN_RB_IDX) {
        RBCell cell = rb_cells[col_img - COL_MIN_RB_IDX];
        Cell prev_cell = getCell(cell.prev_pos);
        Material rb_mat = getMaterialFromID(cell.matID);

        // In the beginning, the cells of the rigidbody need to be "created", so if 
        // the simulation just started, use the cell material
        if (frame < 2 || prev_cell.mat != rb_mat) {
            setCell(pos, rb_mat);
        } else {
            setCell(pos, prev_cell);//rb_mat
        }
    };

    
    //#define DRAW_PHYSICS_COLORS
    #ifdef DRAW_PHYSICS_COLORS
    if (col_img == COL_QD_CLEAR) {
        imageStore(output_color, pos, vec4(0.0, 0.0, 1.0, 1.0));
    } else if (col_img == COL_EMPTY) {
        imageStore(output_color, pos, vec4(0.0, 0.0, 0.0, 1.0));
    } else if (col_img >= COL_MIN_RB_IDX) {
        imageStore(output_color, pos, vec4(1.0, 0.0, 0.0, 1.0));
    };
    barrier();
    #endif

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
