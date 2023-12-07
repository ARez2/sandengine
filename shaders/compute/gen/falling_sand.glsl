#version 430
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

#define SCREEN_IS_BORDER
#define EMPTY_MAX_DISPERSION_CHECK 8
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



#define TYPE_EMPTY 0

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
#define MAT_dirt Material(10, vec4(0.43137255, 0.2784314, 0.14509805, 1), 1.5, vec4(0, 0, 0, 0), TYPE_movable_solid)

Material[11] materials() {
    Material allMaterials[11] = {
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
        MAT_dirt
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
void rule_fall_slide (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, vec4 rand, ivec2 pos) {
    if (!(isType_liquid(self) || self.mat == MAT_sand)) {
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

void rule_fall_slide_dirt (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, vec4 rand, ivec2 pos) {
    if (!(self.mat == MAT_dirt)) {
        return;
    }
    if (down.mat.density < self.mat.density) {
        swap(self, down);
    } else {
        if (rand.y <= 0.01 && right.mat.density < self.mat.density && downright.mat.density < self.mat.density) {
            swap(self, downright);
        } else {

        }
    }
}

void rule_horizontal_slide (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, vec4 rand, ivec2 pos) {
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

void rule_rise_up (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, vec4 rand, ivec2 pos) {
    if (isType_gas(down) &&  !isType_solid(self) && down.mat.density < self.mat.density) {
        swap(down, self);
    } else {
        if (isType_gas(down) &&  !isType_solid(right) && down.mat.density < right.mat.density) {
            swap(down, right);
        } else {

        }
    }
}

void rule_dissolve (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, vec4 rand, ivec2 pos) {
    if (!(self.mat == MAT_smoke)) {
        return;
    }
    if (rand.y <= 0.004 && isType_gas(self)) {
        self = newCell(MAT_EMPTY, pos);
    } else {

    }
}

void rule_grow (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, vec4 rand, ivec2 pos) {
    if (rand.y <= 0.001 && isType_EMPTY(self) && down.mat == MAT_sand && downright.mat == MAT_water) {
        self = newCell(MAT_vine, pos);
    } else {

    }
}

void rule_grow_up (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, vec4 rand, ivec2 pos) {
    if (rand.y <= 0.004 && isType_EMPTY(self) && down.mat == MAT_vine) {
        self = newCell(MAT_vine, pos);
    } else {

    }
}

void rule_die_off (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, vec4 rand, ivec2 pos) {
    if (!(self.mat == MAT_vine)) {
        return;
    }
    if (rand.y <= 0.3 && self.mat == MAT_vine && isType_EMPTY(down)) {
        self = newCell(MAT_EMPTY, pos);
    } else {

    }
}




// =============== CALLERS ===============
void applyMirroredRules(
    inout Cell self,
    inout Cell right,
    inout Cell down,
    inout Cell downright,
    vec4 rand,
    ivec2 pos) {
    rule_fall_slide(self, right, down, downright, rand, pos);
rule_fall_slide_dirt(self, right, down, downright, rand, pos);
rule_horizontal_slide(self, right, down, downright, rand, pos);
rule_rise_up(self, right, down, downright, rand, pos);
rule_dissolve(self, right, down, downright, rand, pos);
rule_grow(self, right, down, downright, rand, pos);
rule_grow_up(self, right, down, downright, rand, pos);
rule_die_off(self, right, down, downright, rand, pos);
}


void applyLeftRules(
    inout Cell self,
    inout Cell right,
    inout Cell down,
    inout Cell downright,
    vec4 rand,
    ivec2 pos) {
    
}

void applyRightRules(
    inout Cell self,
    inout Cell right,
    inout Cell down,
    inout Cell downright,
    vec4 rand,
    ivec2 pos) {
    
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

    if (time < 0.1) {
        setCell(pos, MAT_EMPTY);
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
