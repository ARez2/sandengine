#version 430
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

#define SCREEN_IS_BORDER
#define EMPTY_MAX_DISPERSION_CHECK 8
#define USE_CIRCLE_BRUSH
//#define DEBUG_SHOW_UPDATERECT
//#define DEBUG_SHOW_ORIG_POS
//#define DEBUG_SHOW_MOVERIGHT
#define UP ivec2(0, -1)
#define DOWN ivec2(0, 1)
#define LEFT ivec2(-1, 0)
#define RIGHT ivec2(1, 0)
#define UPLEFT ivec2(-1, -1)
#define UPRIGHT ivec2(1, -1)
#define DOWNLEFT ivec2(-1, 1)
#define DOWNRIGHT ivec2(1, 1)


ivec2[2] getMoveDirs(bool moveRight) {
    if (moveRight) {
        ivec2[2] arr = {
            RIGHT,
            LEFT
        };
        return arr;
    } else {
        ivec2[2] arr = {
            LEFT,
            RIGHT
        };
        return arr;
    }
}
ivec2[2] getMoveDirs(ivec2 pos, bool moveRight) {
    ivec2[2] arr = getMoveDirs(moveRight);
    arr[0] += pos;
    arr[1] += pos;
    return arr;
}


// Gold Noise ©2015 dcerisano@standard3d.com
// - based on the Golden Ratio
// - uniform normalized distribution
// - fastest static noise generator function (also runs at low precision)
// - use with indicated fractional seeding method

const float PHI = 1.61803398874989484820459; // Φ = Golden Ratio 
float gold_noise(in vec2 xy, in float seed) {
    return fract(tan(distance(xy*PHI, xy)*seed)*xy.x);
}



// From Chris Wellons Hash Prospector
// https://nullprogram.com/blog/2018/07/31/
// https://www.shadertoy.com/view/WttXWX
uint hashi(inout uint x)
{
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

// Modified to work with 4 values at once
uvec4 hash4i(inout uint y)
{
    uvec4 x = y * uvec4(213u, 2131u, 21313u, 213132u);
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    y = x.x;
    return x;
}

vec2 old_hash2( vec2 p ) // replace this by something better
{
	p = vec2( dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)) );
	return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

float hash(inout uint x)
{
    return float( hashi(x) ) / float( 0xffffffffU );
}

vec2 hash2(inout uint x)
{
    return vec2(hash(x), hash(x));
}

vec3 hash3(inout uint x)
{
    return vec3(hash(x), hash(x), hash(x));
}

vec4 hash4(inout uint x)
{
    return vec4( hash4i(x) ) / float( 0xffffffffU );
    //return vec4(hash(x), hash(x), hash(x), hash(x));
}

vec4 hash42(uvec2 p)
{
    uint x = p.x*2131u + p.y*2131u*2131u;
    return vec4( hash4i(x) ) / float( 0xffffffffU );
    //return vec4(hash(x), hash(x), hash(x), hash(x));
}

vec4 hash43(uvec3 p)
{
    uint x = p.x*461u + p.y*2131u + p.z*2131u*2131u;
    return vec4( hash4i(x) ) / float( 0xffffffffU );
    //return vec4(hash(x), hash(x), hash(x), hash(x));
}


float _noise( in vec2 p )
{
    const float K1 = 0.366025404; // (sqrt(3)-1)/2;
    const float K2 = 0.211324865; // (3-sqrt(3))/6;

	vec2  i = floor( p + (p.x+p.y)*K1 );
    vec2  a = p - i + (i.x+i.y)*K2;
    float m = step(a.y,a.x); 
    vec2  o = vec2(m,1.0-m);
    vec2  b = a - o + K2;
	vec2  c = a - 1.0 + 2.0*K2;
    vec3  h = max( 0.5-vec3(dot(a,a), dot(b,b), dot(c,c) ), 0.0 );
	vec3  n = h*h*h*h*vec3( dot(a,old_hash2(i+0.0)), dot(b,old_hash2(i+o)), dot(c,old_hash2(i+1.0)));
    return 0.25 + 0.5*dot( n, vec3(70.0) );
}

float noise(vec2 p, int octaves, float lacunarity, float frequency) {
    float f = 0.0;
    
    vec2 p2 = p;
    for (int o = 1; o < octaves + 1; o++) {
        f += 1.0 / float(o) * _noise(p2 * frequency);
        p2 *= lacunarity;
    }
    return f;
}

float noise(vec2 p) {
    return noise(p, 1, 2.0, 0.1);
}


vec2 rotatePoint(vec2 pt, float rot) {
  return mat2(cos(rot), -sin(rot), sin(rot), cos(rot)) * pt;
}

vec2 rotatePoint(vec2 pt, float rot, vec2 origin) {
  return rotatePoint(pt - origin, rot) + origin;
}



ivec2[4] getNeighbours(ivec2 pos) {
    ivec2 neighs[4] = {
        pos + UP,
        pos + LEFT,
        pos + RIGHT,
        pos + DOWN,
    };
    return neighs;
}

ivec2[4] getOnlyDiagonalNeighbours(ivec2 pos) {
    ivec2 neighs[4] = {
        pos + UPRIGHT,
        pos + UPLEFT,
        pos + DOWNRIGHT,
        pos + DOWNLEFT,
    };
    return neighs;
}


#define NEIGH_IDX_UP 0
#define NEIGH_IDX_UPLEFT 1
#define NEIGH_IDX_UPRIGHT 2
#define NEIGH_IDX_LEFT 3
#define NEIGH_IDX_RIGHT 4
#define NEIGH_IDX_DOWN 5
#define NEIGH_IDX_DOWNLEFT 6
#define NEIGH_IDX_DOWNRIGHT 7

ivec2[8] getDiagonalNeighbours(ivec2 pos) {
    ivec2 neighs[8] = {
        pos + DOWN,
        pos + UP,
        pos + DOWNLEFT,
        pos + UPLEFT,
        pos + DOWNRIGHT,
        pos + UPRIGHT,
        pos + RIGHT,
        pos + LEFT,
    };
    return neighs;
}



struct Material {
    int id;
    vec4 color;
    float density;
    vec4 emission;

    int type;
};


struct Cell {
    Material mat;
    ivec2 pos;
};

Cell newCell(Material mat, ivec2 pos) {
    return Cell(mat, pos);
}

struct RBCell {
    int matID;
    ivec2 orig_off;
    ivec2 pos;
    ivec2 prev_pos;
    int rb_idx;
};



//#include "materials.glsl"#define TYPE_EMPTY 0

#define TYPE_NULL 1

#define TYPE_WALL 2

#define TYPE_solid 3

#define TYPE_movable_solid 4

#define TYPE_liquid 5

#define TYPE_gas 6

#define TYPE_plant 7

bool isType_EMPTY(Cell cell) {
    return cell.mat.type == TYPE_EMPTY;
}

bool isType_NULL(Cell cell) {
    return cell.mat.type == TYPE_NULL;
}

bool isType_WALL(Cell cell) {
    return cell.mat.type == TYPE_WALL;
}

bool isType_solid(Cell cell) {
    return cell.mat.type == TYPE_solid || cell.mat.type == TYPE_movable_solid;
}

bool isType_movable_solid(Cell cell) {
    return cell.mat.type == TYPE_movable_solid;
}

bool isType_liquid(Cell cell) {
    return cell.mat.type == TYPE_liquid;
}

bool isType_gas(Cell cell) {
    return cell.mat.type == TYPE_gas;
}

bool isType_plant(Cell cell) {
    return cell.mat.type == TYPE_plant;
}


#define MAT_EMPTY Material(0, vec4(0, 0, 0, 0), 1, vec4(0, 0, 0, 0), TYPE_EMPTY)
#define MAT_NULL Material(1, vec4(1, 0, 1, 1), 0, vec4(0, 0, 0, 0), TYPE_NULL)
#define MAT_WALL Material(2, vec4(0.1, 0.2, 0.3, 1), 9999, vec4(0, 0, 0, 0), TYPE_WALL)
#define MAT_sand Material(3, vec4(1, 1, 0, 1), 1.5, vec4(0, 0, 0, 0), TYPE_movable_solid)
#define MAT_rock Material(4, vec4(0.2, 0.2, 0.2, 1), 4, vec4(0, 0, 0, 0), TYPE_solid)
#define MAT_water Material(5, vec4(0, 0, 1, 0.5), 1.3, vec4(0, 0, 0, 0), TYPE_liquid)
#define MAT_radioactive Material(6, vec4(0.196, 0.55, 0.184, 1), 5, vec4(0.05, 0.7, 0.05, 0.9), TYPE_solid)
#define MAT_smoke Material(7, vec4(0.3, 0.3, 0.3, 0.3), 0.1, vec4(0, 0, 0, 0), TYPE_gas)
#define MAT_toxic_sludge Material(8, vec4(0, 0.7, 0, 0.5), 1.49, vec4(0.7, 0, 0, 0.99999), TYPE_liquid)
#define MAT_vine Material(9, vec4(0.34117648, 0.49803922, 0.24313726, 1), 2.5, vec4(0, 0, 0, 0), TYPE_plant)

Material[10] materials() {
    Material allMaterials[10] = {
        MAT_EMPTY,
MAT_NULL,
MAT_WALL,
MAT_sand,
MAT_rock,
MAT_water,
MAT_radioactive,
MAT_smoke,
MAT_toxic_sludge,
MAT_vine,

    };
    return allMaterials;
}

Material getMaterialFromID(int id) {
    for (int i = 0; i < materials().length(); i++) {
        if (id == materials()[i].id) {
            return materials()[i];
        };
    };
    return MAT_NULL;
}





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



bool outOfBounds(vec2 pos) {
    return pos.x >= simSize.x - 1 || pos.x < 0 || pos.y >= simSize.y - 1 || pos.y < 0;
}
bool outOfBounds(ivec2 pos) {
    return pos.x >= simSize.x - 1 || pos.x < 0 || pos.y >= simSize.y - 1 || pos.y < 0;
}

void swap(inout vec4 a, inout vec4 b) {
    vec4 tmp = a;
    a = b;
    b = tmp;
}
void swap(inout Cell a, inout Cell b) {
    if (a.mat.type == TYPE_WALL || b.mat.type == TYPE_WALL || a.mat.type == TYPE_NULL || b.mat.type == TYPE_NULL) {
        return;
    }
    Cell tmp = a;
    a = b;
    b = tmp;
}

ivec2 getMargolusOffset(int frame) {
    frame = frame % 4;
    if (frame == 1)
        return ivec2(1, 1);
    else if (frame == 2)
       return ivec2(0, 1);
    else if (frame == 3)
        return ivec2(1, 0);
    return ivec2(0, 0);
}

int cellToID(vec4 p) {
    return int(dot(p, vec4(1, 2, 4, 8)));
}

vec4 IDToCell(int id) {
    return vec4(id%2, (id/2)%2, (id/4)%2, (id/8)%2);
}


Cell getCell(ivec2 pos) {
    if (outOfBounds(pos)) {
        #ifdef SCREEN_IS_BORDER
        return newCell(MAT_WALL, pos);
        #endif // SCREEN_IS_BORDER
        return newCell(MAT_NULL, pos);
    };
    ivec4 data = ivec4(texelFetch(input_data, pos, 0));
    // data: ___id___  00000000  00000000  00000000
    int matID = int(data.r);

    return Cell(getMaterialFromID(matID), pos);
}

Cell getCell(ivec2 pos, ivec2 offset) {
    return getCell(pos + offset);
}


bool isCollider(Cell cell) {
    return cell.mat != MAT_EMPTY && cell.mat != MAT_NULL && cell.mat != MAT_WALL;// && !isGas(cell) && !isLiquid(cell)
}

bool isLightObstacle(Cell cell) {
    return cell.mat.emission.rgb == vec3(0.0) && (!isType_EMPTY(cell));
}


vec4 CalculateNewLight(Cell self, Cell right, Cell below, Cell downright) {
    // Calculate the average of neighboring light values
    vec4 sumNeighbors = texelFetch(input_light, right.pos, 0) +
                        texelFetch(input_light, below.pos, 0) +
                        texelFetch(input_light, downright.pos, 0);
    vec4 avgLight = (sumNeighbors) / 3.0;

    // Calculate custom attenuation based on the alpha channel of neighboring cells
    float attenuationRight = right.mat.emission.a;
    float attenuationBelow = below.mat.emission.a;
    float attenuationDownright = downright.mat.emission.a;

    // Calculate weighted average of light values with custom attenuation
    vec4 attenuatedLight = (avgLight * attenuationRight +
                            avgLight * attenuationBelow +
                            avgLight * attenuationDownright) / 3.0;

    return attenuatedLight + self.mat.emission;
}



bool gt(vec3 a, vec3 b) {
    return a.x > b.x && a.y > b.y && a.z > b.z;
}

void setCell(ivec2 pos, Cell cell) {
    vec4 color = cell.mat.color;
    
    // TODO: Modify noise based on material
    if (cell.mat != MAT_EMPTY) {
        float rand = noise(vec2(pos.x, pos.y), 3, 2.0, 0.25) * 0.25;
        color.r = clamp(color.r - rand, 0.0, 1.0);
        color.g = clamp(color.g - rand, 0.0, 1.0);
        color.b = clamp(color.b - rand, 0.0, 1.0);
    };
    
    //imageStore(output_effects, pos, vec4(cell.mat.emission, 1.0));
    ivec4 data = ivec4(cell.mat.id, 0, 0, 0);
    imageStore(output_data, pos, data);

    ivec2[8] neighs = getDiagonalNeighbours(pos);
    Cell[8] neighCells;
    for (int n = 0; n < neighs.length(); n++) {
        neighCells[n] = getCell(neighs[n]);
    }

    // int numColliders = int(isCollider(neighCells[3])) + int(isCollider(neighCells[4])) + int(isCollider(neighCells[0])) + int(isCollider(neighCells[5]));
    // if (setCollision && isCollider(cell) && numColliders < 4) {
    //     imageStore(collision_data, pos / 8, max(imageLoad(collision_data, pos / 8), vec4(vec3(1.0), 0.1)));
    // }
    
    vec4 light;
    if (cell.mat.emission.rgb != vec3(0.0)) {
        light = cell.mat.emission;
    } else if (pos.y == 0) {
        light = vec4(vec3(1.0), 0.999999);
    } else {
        vec4 avg_light = vec4(0.0);
        vec4 max_light = vec4(0.0);
        float max_falloff = 0.0;

        int num_lightsources = 0;
        for (int n = 0; n < neighs.length(); n++) {
            Cell neigh = neighCells[n];
            ivec2 neighPos = neigh.pos;
            if (outOfBounds(neighPos)) {
                continue;
            }
            bool neighObstacle = isLightObstacle(neigh);
            vec4 light_data = texelFetch(input_light, neighPos, 0) * vec4(vec3(float(!neighObstacle)), 1.0);

            float falloff;
            if (light_data.a == 0.0) {
                falloff = max_falloff;
            } else {
                falloff = light_data.a;
            }
            vec4 light = vec4(light_data.rgb * light_data.a, falloff);
            avg_light += light;
            max_falloff = max(falloff, max_falloff);
            num_lightsources += 1;

            //               0.96, (light_data.a - (1.0 - light_data.a) * 100.0)
            vec4 m = vec4(light.rgb, light.a);
            max_light = max(max_light, m);
            
        }
        if (num_lightsources > 0) {
            avg_light /= num_lightsources;
        }
        // Max light is fast but produces star like patterns and average is too slow, so lerp
        //                                     0.1, 0.25
        light = vec4(mix(avg_light.rgb, max_light.rgb, 0.5), avg_light.a);
        
    }
    imageStore(output_light, pos, light);
    imageStore(output_color, pos, color);
}
void setCell(ivec2 pos, Material mat) {
    setCell(pos, newCell(mat, pos));
}




// =============== RULES ===============
void rule_fall_slide (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, ivec2 pos) {
    if (!(isType_movable_solid(self) || isType_liquid(self))) {
    return;
}

    if (down.mat.density < self.mat.density) {
    swap(self, down);
} else {
    if (right.mat.density < self.mat.density && downright.mat.density < self.mat.density) {
    swap(self, downright);
} else {
    
}
}
}

void rule_horizontal_slide (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, ivec2 pos) {
    if (!(isType_liquid(self))) {
    return;
}

    if (isType_liquid(self) && right.mat.density < self.mat.density) {
    swap(self, right);
} else {
    if (isType_liquid(down) && downright.mat.density < down.mat.density) {
    swap(down, downright);
} else {
    
}
}
}

void rule_rise_up (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, ivec2 pos) {
    

    if (isType_gas(down) &&  !isType_solid(self) && down.mat.density < self.mat.density) {
    swap(down, self);
} else {
    if (isType_gas(down) &&  !isType_solid(right) && down.mat.density < right.mat.density) {
    swap(down, right);
} else {
    
}
}
}

void rule_grow (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, ivec2 pos) {
    

    if (isType_EMPTY(self) && down.mat == MAT_sand && downright.mat == MAT_water) {
    self = newCell(MAT_vine, pos);
} else {
    
}
}

void rule_grow_up (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, ivec2 pos) {
    

    if (isType_EMPTY(self) && down.mat == MAT_vine) {
    self = newCell(MAT_vine, pos);
} else {
    
}
}




// =============== CALLERS ===============
void applyMirroredRules(
    inout Cell self,
    inout Cell right,
    inout Cell down,
    inout Cell downright,
    ivec2 pos) {
    rule_fall_slide(self, right, down, downright, pos);
rule_horizontal_slide(self, right, down, downright, pos);
rule_grow(self, right, down, downright, pos);
rule_grow_up(self, right, down, downright, pos);
}


void applyLeftRules(
    inout Cell self,
    inout Cell right,
    inout Cell down,
    inout Cell downright,
    ivec2 pos) {
    
}

void applyRightRules(
    inout Cell self,
    inout Cell right,
    inout Cell down,
    inout Cell downright,
    ivec2 pos) {
    rule_rise_up(self, right, down, downright, pos);
}





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
