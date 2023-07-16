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
    vec3 emission;

    int type;
};

#define TYPE_EMPTY 0
#define TYPE_SOLID 1
#define TYPE_MOVSOLID 2
#define TYPE_LIQUID 3
#define TYPE_GAS 4

#define EMPTY Material(0, vec4(0.0, 0.0, 0.0, 0.0), 1.0,  0, vec3(0.0, 0.0, 0.0), TYPE_EMPTY)
#define SAND  Material(1, vec4(1.0, 1.0, 0.0, 1.0), 3.0,  1, vec3(0.0, 0.0, 0.0), TYPE_MOVSOLID)
#define SOLID Material(2, vec4(0.4, 0.4, 0.4, 1.0), 4.0,  0, vec3(0.0, 0.0, 0.0), TYPE_SOLID)
#define WATER Material(3, vec4(0.0, 0.0, 1.0, 0.5), 2.0,  4, vec3(0.0, 0.0, 0.0), TYPE_LIQUID)
#define NULL  Material(4, vec4(1.0, 0.0, 1.0, 1.0), 0.0,  0, vec3(0.0, 0.0, 0.0), TYPE_EMPTY)
#define WALL  Material(5, vec4(0.1, 0.1, 0.1, 1.0), 99.0, 0, vec3(0.0, 0.0, 0.0), TYPE_SOLID)

#define RADIOACTIVE Material(6, vec4(0.196, 0.55, 0.184, 1.0), 5.0,  0, vec3(0.05, 0.7, 0.05), TYPE_SOLID)
#define SMOKE Material(7, vec4(0.55, 0.55, 0.55, 0.3), 0.1,  1, vec3(0.0, 0.0, 0.00), TYPE_GAS)
#define TOXIC Material(8, vec4(0.0, 0.7, 0.2, 0.5), 1.8,  2, vec3(0.0, 0.5, 0.0), TYPE_LIQUID)






struct Cell {
    Material mat;
    ivec2 origPos;
    ivec2 pos;
};




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
        return Cell(WALL, pos, pos);
        #endif // SCREEN_IS_BORDER
        return Cell(NULL, pos, pos);
    };
    ivec4 data = ivec4(texelFetch(input_data, pos, 0));
    // data: orig_pos.x  orig_pos.y  ___id___  00000000
    ivec2 orig_pos = ivec2(data.r, data.g);
    int matID = int(data.b);

    return Cell(getMaterialFromID(matID), orig_pos, pos);
}

Cell getCell(ivec2 pos, ivec2 offset) {
    return getCell(pos + offset);
}


bool isCollider(Cell cell) {
    return cell.mat != EMPTY && cell.mat != NULL && cell.mat != WALL;// && !isGas(cell) && !isLiquid(cell)
}

bool isLightObstacle(Cell cell) {
    return cell.mat.emission == vec3(0.0) && (isSolid(cell) || isMovSolid(cell));
}


void setCell(ivec2 pos, Cell cell, bool setCollision) {
    vec4 color = cell.mat.color;
    
    // TODO: Modify noise based on material
    if (cell.mat != EMPTY) {
        float rand = noise(vec2(cell.origPos), 3, 2.0, 0.1) * 0.25;
        color.r = clamp(color.r - rand, 0.0, 1.0);
        color.g = clamp(color.g - rand, 0.0, 1.0);
        color.b = clamp(color.b - rand, 0.0, 1.0);
    };
    
    //imageStore(output_effects, pos, vec4(cell.mat.emission, 1.0));
    ivec4 data = ivec4(cell.origPos.x, cell.origPos.y, cell.mat.id, 1);
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
    
    
    vec4 light;
    if (cell.mat.emission != vec3(0.0)) {
        light = vec4(cell.mat.emission, 1.0);
    } else {
        vec3 avg_light = vec3(0.0);
        vec3 max_light = vec3(0.0);
        vec2 offsetsToLight = vec2(0.0);
        
        int num_lightsources = 0;
        for (int n = 0; n < neighs.length(); n++) {
            Cell neigh = neighCells[n];
            ivec2 neighPos = neigh.pos;
            bool neighObstacle = isLightObstacle(neigh);
            vec3 light_data = texelFetch(input_light, neighPos, 0).rgb * float(!neighObstacle);
            if (light_data != vec3(0.0) || neigh.mat == EMPTY) {
                num_lightsources += 1;
                vec3 light = light_data * 0.99999;
                avg_light += light;

                vec3 m = light * 0.96;
                max_light = max(max_light, m);
            }
            
            offsetsToLight += (neighPos - pos) * length(light_data);
        }
        if (num_lightsources > 0) {
            avg_light /= num_lightsources;
        }
        //                                     0.1
        light = vec4(mix(avg_light, max_light, 0.25), 1.0);
        //vec2 dirToLight = normalize(offsetsToLight);
        //imageStore(output_color, pos, vec4(dirToMaxLight.x, dirToMaxLight.y, 0.0, 1.0));
    }
    imageStore(output_light, pos, light);
    vec4 ambientLight = vec4(vec3(0.3), 1.0);
    if (cell.mat == EMPTY) {
        imageStore(output_color, pos, light);
    } else {
        imageStore(output_color, pos, color * min(light + ambientLight, vec4(1.0)));
    }
}
void setCell(ivec2 pos, Material mat, bool setCollision) {
    setCell(pos, Cell(mat, pos, pos), setCollision);
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






ivec2 movSolidStep(Cell self, bool moveRight, bool isSelf) {
    float ownDensity = self.mat.density;
    ivec2 pos = self.pos;

    Cell below;
    Cell left;
    Cell right;
    Cell downleft;
    Cell downright;
    if (isSelf) {
        below = neighbours[NEIGH_IDX_DOWN];
        left = neighbours[NEIGH_IDX_LEFT];
        right = neighbours[NEIGH_IDX_RIGHT];
        downleft = neighbours[NEIGH_IDX_DOWNLEFT];
        downright = neighbours[NEIGH_IDX_DOWNRIGHT];
    } else {
        below = getCell(pos + DOWN);
        left = getCell(pos + LEFT);
        right = getCell(pos + RIGHT);
        downleft = getCell(pos + DOWNLEFT);
        downright = getCell(pos + DOWNRIGHT);
    }
    bool canMoveDown = below.mat.density < ownDensity
        && (!shouldDoMovSolidStep(left) || (left.mat.density > downleft.mat.density || left.mat.density <= below.mat.density || left.mat.density > getCell(left.pos + DOWNLEFT).mat.density))
        && (!shouldDoMovSolidStep(right) || (right.mat.density > downright.mat.density || right.mat.density <= below.mat.density || right.mat.density > getCell(right.pos + DOWNRIGHT).mat.density));
    if (canMoveDown) {
        return pos + DOWN;
    };

    Cell firstTarget;
    Cell secondTarget;
    if (moveRight) {
        firstTarget = downright;
        secondTarget = downleft;
    } else {
        firstTarget = downleft;
        secondTarget = downright;
    }
    
    if (firstTarget.mat.density < ownDensity) {
        return firstTarget.pos;
    }

    if (secondTarget.mat.density < ownDensity) {
        return secondTarget.pos;
    }

    return pos;
}





ivec2 gasStep(Cell self, bool moveRight, bool isSelf) {
    float ownDensity = self.mat.density;
    ivec2 pos = self.pos;


    Cell above;
    Cell left;
    Cell right;
    Cell upleft;
    Cell upright;
    if (isSelf) {
        above = neighbours[NEIGH_IDX_UP];
        left = neighbours[NEIGH_IDX_LEFT];
        right = neighbours[NEIGH_IDX_RIGHT];
        upleft = neighbours[NEIGH_IDX_UPLEFT];
        upright = neighbours[NEIGH_IDX_UPRIGHT];
    } else {
        above = getCell(pos + UP);
        left = getCell(pos + LEFT);
        right = getCell(pos + RIGHT);
        upleft = getCell(pos + UPLEFT);
        upright = getCell(pos + UPRIGHT);
    }
    bool canMoveUp = ownDensity < above.mat.density && !isSolid(above)
        && (!shouldDoGasStep(left) || (left.mat.density < upleft.mat.density || left.mat.density >= above.mat.density || left.mat.density < getCell(left.pos + UPLEFT).mat.density))
        && (!shouldDoGasStep(right) || (right.mat.density < upright.mat.density || right.mat.density >= above.mat.density || right.mat.density < getCell(right.pos + UPRIGHT).mat.density));
    if (canMoveUp) {
        return pos + UP;
    };


    Cell firstTarget;
    Cell secondTarget;
    if (moveRight) {
        firstTarget = upright;
        secondTarget = upleft;
    } else {
        firstTarget = upleft;
        secondTarget = upright;
    }

    if (ownDensity < firstTarget.mat.density && (firstTarget.mat == EMPTY || isGas(firstTarget))) {
        return firstTarget.pos;
    }

    if (ownDensity < secondTarget.mat.density && (secondTarget.mat == EMPTY || isGas(secondTarget))) {
        return secondTarget.pos;
    }

    return pos;
}





//Make water look for sand above which it could swap to
bool canLiquidMoveHere(ivec2 pos, bool moveRight, bool includeHorizontal) {
    ivec2[3] neighs = {
        pos + UP,
        pos + UPLEFT,
        pos + UPRIGHT,
    };
    for (int n = 0; n < neighs.length(); n++) {
        Cell neigh = getCell(neighs[n]);
        if ((shouldDoMovSolidStep(neigh) && movSolidStep(neigh, moveRight, false) == pos) || isLiquid(neigh)) {
            return false;
        };
    };
    return true;
}

bool liquidMoveCondition(Cell liquid, ivec2 dir, int checkLength, bool moveRight, bool isMinor) {
    ivec2 checkpos = liquid.pos + dir * checkLength;
    Cell target = getCell(checkpos);
    if (target.mat.density >= liquid.mat.density) {
        return false;
    };

    // Had to implement a "priority"
    // Imagine this setup (moveRight=true):
    //             X  Y|
    // X thinks: "Since its moveRight, I have priority and
    //            should move right next to Y"
    // Y thinks: "Since I cannot move right, I can move left
    //            right next to X."
    // if both act, they would swap positions:
    //              YX |
    // This is not desired. Instead, X knows if it goes left 
    // as a minor (against the moveRight direction)

    // When it does it checks a certain amount of cells in the direction
    // it wants to move to and if there is a liquid, that could potentially
    // move, resulting in such a swap, X does not move
    if (isMinor) {
        for (int c = checkLength + 1; c < EMPTY_MAX_DISPERSION_CHECK; c++) {
            Cell ccell = getCell(liquid.pos + dir * c);
            if (ccell.mat.density < liquid.mat.density) {
                continue;
            }
            // Found a liquid that could move into or over our target position
            if (shouldDoLiquidStep(ccell) && ccell.pos.x - dir.x * ccell.mat.dispersion >= checkpos.x) {
                return false;
            }
        }
    }

    //return target.mat.density < liquid.mat.density;
    return canLiquidMoveHere(checkpos, moveRight, false);
}


// TODO: Apply liquid horizontal step between 2 liquids

ivec2 liquidStep(Cell self, bool moveRight, bool isSelf) {
    float ownDensity = self.mat.density;
    ivec2 pos = self.pos;

    ivec2[2] movepositions = getMoveDirs(pos + UP, moveRight);
    ivec2[3] positions1 = {
        pos + UP,
        movepositions[0],
        movepositions[1]
    };
    for (int p = 0; p < positions1.length(); p++) {
        ivec2 position = positions1[p];
        Cell target = getCell(position);
        if (shouldDoMovSolidStep(target) && movSolidStep(target, moveRight, false) == pos) {
            return position;
        }
    }

    ivec2 movSolidRes = movSolidStep(self, moveRight, isSelf);
    if (movSolidRes != pos) {
        return movSolidRes;
    };

    ivec2[2] positions = getMoveDirs(moveRight);
    
    int dispersion = self.mat.dispersion;
    ivec2 last_possible_pos = pos;
    for (int disp = 1; disp <= dispersion; disp++) {
        if (liquidMoveCondition(self, positions[0], disp, moveRight, false)) {
            last_possible_pos = pos + positions[0] * disp;
        } else if (liquidMoveCondition(self, positions[1], disp, moveRight, true)) {
            last_possible_pos = pos + positions[1] * disp;
        } else {
            break;
        };
    };

    return last_possible_pos;
}





bool tryPullMovSolid(Cell self, bool moveRight) {
    if (shouldDoMovSolidStep(neighbours[NEIGH_IDX_UP]) && movSolidStep(neighbours[NEIGH_IDX_UP], moveRight, false) == self.pos) {
        pullCell(self.pos + UP, self.pos);
        return true;
    }

    ivec2 firstPos;
    ivec2 secondPos;
    Cell firstTarget;
    Cell secondTarget;
    if (moveRight) {
        firstPos = self.pos + UPLEFT;
        secondPos = self.pos + UPRIGHT;
        firstTarget = neighbours[NEIGH_IDX_UPLEFT];
        secondTarget = neighbours[NEIGH_IDX_UPRIGHT];
    } else {
        firstPos = self.pos + UPRIGHT;
        secondPos = self.pos + UPLEFT;
        firstTarget = neighbours[NEIGH_IDX_UPRIGHT];
        secondTarget = neighbours[NEIGH_IDX_UPLEFT];
    }

    if (shouldDoMovSolidStep(firstTarget) && movSolidStep(firstTarget, moveRight, false) == self.pos) {
        pullCell(firstPos, self.pos);
        return true;
    }

    if (shouldDoMovSolidStep(secondTarget) && movSolidStep(secondTarget, moveRight, false) == self.pos) {
        pullCell(secondPos, self.pos);
        return true;
    }

    return false;
}


bool tryPullGas(Cell self, bool moveRight) {
    ivec2[2] movePositions = getMoveDirs(self.pos + DOWN, moveRight);
    ivec2[3] positions = {
        self.pos + DOWN,
        movePositions[0],
        movePositions[1]
    };

    for (int p = 0; p < positions.length(); p++) {
        Cell c = getCell(positions[p]);
        if (shouldDoGasStep(c) && gasStep(c, moveRight, false) == self.pos) {
            pullCell(positions[p], self.pos);
            return true;
        }
    }
    return false;
}


void emptyStep(Cell self, bool moveRight) {
    ivec2 pos = self.pos;
    
    if (tryPullMovSolid(self, moveRight)) {
        return;
    }
    
    ivec2[2] positions = getMoveDirs(moveRight);
    int dispersion = EMPTY_MAX_DISPERSION_CHECK;
    ivec2 last_possible_pos = pos;
    // Horizontal, account for dispersion
    for (int disp = dispersion; disp > 0; disp--) {
        ivec2 first_checkpos = pos + positions[0] * disp;
        ivec2 second_checkpos = pos + positions[1] * disp;
        Cell first = getCell(first_checkpos);
        Cell second = getCell(second_checkpos);
        if (shouldDoLiquidStep(first) && liquidStep(first, moveRight, false) == pos) {
            pullCell(first_checkpos, pos);
            return;
        }
        if (shouldDoLiquidStep(second) && liquidStep(second, moveRight, false) == pos) {
            pullCell(second_checkpos, pos);
            return;
        };
    };

    ivec2[2] movepositions = getMoveDirs(pos + DOWN, moveRight);
    ivec2[3] positions2 = {
        pos + DOWN,
        movepositions[0],
        movepositions[1]
    };
    for (int p = 0; p < positions2.length(); p++) {
        ivec2 position = positions2[p];
        Cell target = getCell(position);
        if (shouldDoLiquidStep(target) && liquidStep(target, moveRight, false) == pos) {
            pullCell(position, pos);
            return;
        }
    }

    if (tryPullGas(self, moveRight)) {
        return;
    }

    setCell(pos, self, false);
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

    float downspread = 0.5; // 0.5
    float rand2 = 0.5; // 0.9

    // Sand
    if (downright.mat == SAND) {
        if (right.mat.density < SAND.density) {
            if (v.z < 0.9) {
                swap(downright, right);
            }
        } else if (self.mat.density < SAND.density && down.mat.density < SAND.density) {
            swap(downright, self);
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
    if (time < 0.2) {
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
