#version 450
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
        pos + UP,
        pos + UPLEFT,
        pos + UPRIGHT,
        pos + LEFT,
        pos + RIGHT,
        pos + DOWN,
        pos + DOWNLEFT,
        pos + DOWNRIGHT,
    };
    return neighs;
}



struct Material {
    int id;
    vec4 color;
    float density;
    int dispersion;
    vec4 emission;

    int type;
};

#define TYPE_EMPTY 0
#define TYPE_SOLID 1
#define TYPE_MOVSOLID 2
#define TYPE_LIQUID 3
#define TYPE_GAS 4

#define EMPTY Material(0, vec4(0.0, 0.0, 0.0, 0.0), 1.0,  0, vec4(0.0), TYPE_EMPTY)
#define SAND  Material(1, vec4(1.0, 1.0, 0.0, 1.0), 3.0,  1, vec4(0.0), TYPE_MOVSOLID)
#define SOLID Material(2, vec4(0.4, 0.4, 0.4, 1.0), 4.0,  0, vec4(0.0), TYPE_SOLID)
#define WATER Material(3, vec4(0.0, 0.0, 1.0, 0.5), 2.0,  4, vec4(0.0), TYPE_LIQUID)
#define NULL  Material(4, vec4(1.0, 0.0, 1.0, 1.0), 0.0,  0, vec4(0.0), TYPE_EMPTY)
#define WALL  Material(5, vec4(0.1, 0.1, 0.1, 1.0), 99.0, 0, vec4(0.0), TYPE_SOLID)

#define RADIOACTIVE Material(6, vec4(0.196, 0.55, 0.184, 1.0), 5.0,  0, vec4(0.05, 0.7, 0.05, 0.9), TYPE_SOLID)
#define SMOKE Material(7, vec4(0.55, 0.55, 0.55, 0.3), 0.1,  1, vec4(0.0), TYPE_GAS)
#define TOXIC Material(8, vec4(0.0, 0.7, 0.2, 0.5), 1.8,  2, vec4(0.0, 0.5, 0.0, 0.99999), TYPE_LIQUID)






struct Cell {
    Material mat;
    ivec2 pos;
};

Cell newCell(Material mat, ivec2 pos) {
    return Cell(mat, pos);
}



#define NUM_MATERIALS 9

Material[NUM_MATERIALS] materials() {
    Material allMaterials[NUM_MATERIALS] = {
        EMPTY,
        SAND,
        SOLID,
        WATER,
        NULL,
        WALL,
        RADIOACTIVE,
        SMOKE,
        TOXIC,
    };
    return allMaterials;
}

Material getMaterialFromID(int id) {
    for (int i = 0; i < materials().length(); i++) {
        if (id == materials()[i].id) {
            return materials()[i];
        };
    };
    return NULL;
}

bool isSolid(Cell cell) {
    return cell.mat.type == TYPE_SOLID;
}

bool isLiquid(Cell cell) {
    return cell.mat.type == TYPE_LIQUID;
}

bool isGas(Cell cell) {
    return cell.mat.type == TYPE_GAS;
}

bool isMovSolid(Material mat) {
    return mat.type == TYPE_MOVSOLID;
}
bool isMovSolid(Cell cell) {
    return cell.mat.type == TYPE_MOVSOLID;
}


bool shouldDoMovSolidStep(Cell cell) {
    return isMovSolid(cell) || isLiquid(cell);
}
bool shouldDoLiquidStep(Cell cell) {
    return isLiquid(cell);
}
bool shouldDoGasStep(Cell cell) {
    return isGas(cell);
}




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




bool outOfBounds(vec2 pos) {
    return pos.x >= simSize.x || pos.x < 0 || pos.y >= simSize.y || pos.y < 0;
}
bool outOfBounds(ivec2 pos) {
    return pos.x >= simSize.x || pos.x < 0 || pos.y >= simSize.y || pos.y < 0;
}

void swap(inout vec4 a, inout vec4 b) {
    vec4 tmp = a;
    a = b;
    b = tmp;
}
void swap(inout Cell a, inout Cell b) {
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
        return newCell(WALL, pos);
        #endif // SCREEN_IS_BORDER
        return newCell(NULL, pos);
    };
    ivec4 data = ivec4(texelFetch(input_data, pos, 0));
    // data: ___id___  00000000  00000000  00000000
    int matID = int(data.r);

    return newCell(getMaterialFromID(matID), pos);
}

Cell getCell(ivec2 pos, ivec2 offset) {
    return getCell(pos + offset);
}


bool isCollider(Cell cell) {
    return cell.mat != EMPTY && cell.mat != NULL && cell.mat != WALL;// && !isGas(cell) && !isLiquid(cell)
}

bool isLightObstacle(Cell cell) {
    return cell.mat.emission.rgb == vec3(0.0) && (isSolid(cell) || isMovSolid(cell));
}


bool gt(vec3 a, vec3 b) {
    return a.x > b.x && a.y > b.y && a.z > b.z;
}

void setCell(ivec2 pos, Cell cell, bool setCollision) {
    vec4 color = cell.mat.color;
    
    // TODO: Modify noise based on material
    if (cell.mat != EMPTY) {
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

    int numColliders = int(isCollider(neighCells[3])) + int(isCollider(neighCells[4])) + int(isCollider(neighCells[0])) + int(isCollider(neighCells[5]));
    if (setCollision && isCollider(cell) && numColliders < 4) {
        imageStore(collision_data, pos / 8, max(imageLoad(collision_data, pos / 8), vec4(vec3(1.0), 0.1)));
    }
    
    vec4 ambientLight = vec4(vec3(0.3), 1.0);
    vec4 light;
    if (cell.mat.emission.rgb != vec3(0.0)) {
        light = cell.mat.emission;
    } else if (pos.y == 0) {
        light = vec4(vec3(1.0), 0.9999999);
    } else {
        vec3 avg_light = vec3(0.0);
        vec3 max_light = vec3(0.0);
        float avg_falloff = 0.0;
        int num_falloff = 0;

        int num_lightsources = 0;
        for (int n = 0; n < neighs.length(); n++) {
            Cell neigh = neighCells[n];
            ivec2 neighPos = neigh.pos;
            bool neighObstacle = isLightObstacle(neigh);
            vec4 light_data = texelFetch(input_light, neighPos, 0) * vec4(vec3(float(!neighObstacle)), 1.0);
            if ((gt(light_data.rgb, vec3(0.0)) && light_data.a > 0.0) || neigh.mat == EMPTY) {
                num_lightsources += 1;
                vec3 light = light_data.rgb * light_data.a * (1/length(light_data.rgb));
                avg_light += light;
                if (light_data.a > 0.0) {
                    avg_falloff += light_data.a;
                    num_falloff += 1;
                }

                //               0.96, (light_data.a - (1.0 - light_data.a) * 100.0)
                vec3 m = light * (light_data.a * 0.9);
                max_light = max(max_light, m);
            }
            
        }
        if (num_lightsources > 0) {
            avg_light /= num_lightsources;
        }
        if (num_falloff> 0) {
            avg_falloff /= float(num_falloff);
        }
        // Max light is fast but produces star like patterns and average is too slow, so lerp
        //                                     0.1, 0.25
        light = vec4(mix(avg_light.rgb, max_light, 0.25), avg_falloff);
        
    }
    imageStore(output_light, pos, light);
    
    // if (cell.mat == EMPTY) {
    //     //imageStore(output_color, pos, light);
    //     imageStore(output_color, pos, color * min(light + ambientLight, vec4(1.0)));
    // } else {
    //     imageStore(output_color, pos, color * min(light + ambientLight, vec4(1.0)));
    // }
    imageStore(output_color, pos, color);
    // if (light.a < 1.0) {
    //     imageStore(output_color, pos, vec4(vec3(1.0 - light.a) * 30.0, 1.0));
    // }
}
void setCell(ivec2 pos, Material mat, bool setCollision) {
    setCell(pos, newCell(mat, pos), setCollision);
}


// Copies the data from another position to this position
void pullCell(ivec2 from, ivec2 to) {
    Cell other = getCell(from);
    if (isSolid(other)) {
        setCell(to, EMPTY, false);
    } else {
        setCell(to, other, false);
    }
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

    if (self.mat == EMPTY && right.mat == EMPTY && down.mat == EMPTY && downright.mat == EMPTY) {
        return newCell(EMPTY, pos_rounded);
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
            down = newCell(EMPTY, pos_rounded);
        } else {
            if (!isSolid(self) && down.mat.density < self.mat.density) {
                swap(down, self);
            } else if (!isSolid(right) && down.mat.density < right.mat.density) {
                swap(down, right);
            }
        }
    } else if (shouldDoLiquidStep(down)) {
        if (downright.mat.density < down.mat.density) {
            swap(down, downright);
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

    // Maybe pos
    return newCell(EMPTY, pos_rounded);
}



void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= simSize.x || pos.x < 0 || pos.y >= simSize.y || pos.y < 0) {
        return;
    };

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
