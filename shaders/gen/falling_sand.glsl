#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

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



float hash( uint n ) {
    // integer hash copied from Hugo Elias
	n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float( n & uint(0x7fffffffU))/float(0x7fffffff);
}
vec2 hash2( vec2 p ) // replace this by something better
{
	p = vec2( dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)) );
	return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}
vec3 hash3( uint n ) 
{
    // integer hash copied from Hugo Elias
	n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    uvec3 k = n * uvec3(n,n*16807U,n*48271U);
    return vec3( k & uvec3(0x7fffffffU))/float(0x7fffffff);
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
	vec3  n = h*h*h*h*vec3( dot(a,hash2(i+0.0)), dot(b,hash2(i+o)), dot(c,hash2(i+1.0)));
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


float random(vec2 st)
{
    return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
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

ivec2[8] getDiagonalNeighbours(ivec2 pos, bool moveRight) {
    ivec2 neighs[8];
    if (moveRight) {
        ivec2 neighs[8] = {
            pos + UP,
            pos + UPRIGHT,
            pos + UPLEFT,
            pos + RIGHT,
            pos + LEFT,
            pos + DOWN,
            pos + DOWNLEFT,
            pos + DOWNRIGHT,
        };
    } else {
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
    }
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






Material[9] materials() {
    Material allMaterials[9] = {
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
// } params;
uniform bool moveRight;
uniform vec2 mousePos;
uniform uint brushSize;
uniform int brushMaterial;
uniform float time;

layout(binding = 4) uniform sampler2D input_light;
layout(rgba32f, binding = 5) uniform image2D output_light;
layout(rgba32f, binding = 6) uniform image2D output_effects;


bool outOfBounds(vec2 pos) {
    ivec2 image_size = textureSize(input_data, 0);
    return pos.x >= image_size.x || pos.x < 0 || pos.y >= image_size.y || pos.y < 0;
}
bool outOfBounds(ivec2 pos) {
    ivec2 image_size = textureSize(input_data, 0);
    return pos.x >= image_size.x || pos.x < 0 || pos.y >= image_size.y || pos.y < 0;
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


void setCell(ivec2 pos, Cell cell) {
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
    imageStore(output_color, pos, color);
}
void setCell(ivec2 pos, Material mat) {
    setCell(pos, Cell(mat, pos, pos));
}


// Copies the data from another position to this position
void pullCell(ivec2 from, ivec2 to) {
    Cell other = getCell(from);
    if (!isSolid(other)) {
        setCell(to, other);
    } else {
        setCell(to, EMPTY);
    }
}






ivec2 movSolidStep(Cell self, bool moveRight) {
    float ownDensity = self.mat.density;
    ivec2 pos = self.pos;

    if (getCell(pos + DOWN).mat.density < ownDensity) {
        return pos + DOWN;
    };

    ivec2[2] positions = getMoveDirs(pos + DOWN, moveRight);
    for (int p = 1; p < positions.length(); p++) {
        Cell target = getCell(positions[p]);
        Cell above_target = getCell(target.pos + UP);
        if (target.mat.density < ownDensity && (!shouldDoMovSolidStep(above_target) || above_target.mat.density < ownDensity || above_target.mat.density < target.mat.density)) {
            return positions[p];
        };
    }

    return pos;
}





ivec2 gasStep(Cell self, bool moveRight) {
    float ownDensity = self.mat.density;
    ivec2 pos = self.pos;

    Cell above = getCell(pos + UP);
    if (ownDensity < above.mat.density && !isSolid(above)) {
        return pos + UP;
    };

    ivec2[2] positions = getMoveDirs(pos + UP, moveRight);
    for (int p = 1; p < positions.length(); p++) {
        Cell target = getCell(positions[p]);
        Cell below_target = getCell(target.pos + DOWN);
        if (ownDensity < target.mat.density && !isSolid(target) && (!(shouldDoGasStep(below_target)) || below_target.mat.density > ownDensity || below_target.mat.density > target.mat.density)) {
            return positions[p];
        };
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
        if ((shouldDoMovSolidStep(neigh) && movSolidStep(neigh, moveRight) == pos) || isLiquid(neigh)) {
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

    return canLiquidMoveHere(checkpos, moveRight, false);
}


// TODO: Apply liquid horizontal step between 2 liquids

ivec2 liquidStep(Cell self, bool moveRight) {
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
        if (shouldDoMovSolidStep(target) && movSolidStep(target, moveRight) == pos) {
            //pullCell(position, pos);
            return position;
        }
    }

    ivec2 movSolidRes = movSolidStep(self, moveRight);
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
    ivec2[2] movePositions = getMoveDirs(self.pos + UP, moveRight);
    ivec2[3] positions = {
        self.pos + UP,
        movePositions[0],
        movePositions[1]
    };

    for (int p = 0; p < positions.length(); p++) {
        Cell c = getCell(positions[p]);
        if (shouldDoMovSolidStep(c) && movSolidStep(c, moveRight) == self.pos) {
            pullCell(positions[p], self.pos);
            return true;
        }
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
        if (shouldDoGasStep(c) && gasStep(c, moveRight) == self.pos) {
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
        if (isLiquid(first) && liquidStep(first, moveRight) == pos) {
            pullCell(first_checkpos, pos);
            return;
        }
        if (isLiquid(second) && liquidStep(second, moveRight) == pos) {
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
        if (shouldDoLiquidStep(target) && liquidStep(target, moveRight) == pos) {
            pullCell(position, pos);
            return;
        }
    }

    if (tryPullGas(self, moveRight)) {
        return;
    }

    setCell(pos, self);
}





// Returns the next position of the cell
void update(ivec2 pos) {
    Cell self = getCell(pos);
    
    if (self.mat == NULL) {
        setCell(pos, self);
        return;
    };
    bool moveRight = moveRight;

    if (self.mat == EMPTY) {
        emptyStep(self, moveRight);
    } else if (isMovSolid(self)) {
        ivec2 res = movSolidStep(self, moveRight);
        if (res == pos) {
            setCell(pos, self);
        } else {
            pullCell(res, pos);
        };
    } else if (isLiquid(self)) {
        ivec2 res = liquidStep(self, moveRight);
        if (res != pos) {
            pullCell(res, pos);
        } else {
            setCell(pos, self);
        };
    } else if (isSolid(self)) {
        setCell(pos, self);
    } else if (isGas(self)) {
        ivec2 res = gasStep(self, moveRight);
        if (res == pos) {
            setCell(pos, self);
        } else {
            pullCell(res, pos);
        };
    }
}


void main() {
    ivec2 input_size = imageSize(output_color);

    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= input_size.x || pos.x < 0 || pos.y >= input_size.y || pos.y < 0) {
        return;
    };

    // Process input
    vec2 mousepos = mousePos * vec2(input_size);
    vec2 diffMouse = abs(vec2(mousepos - pos));
    bool applyBrush = false;
    #ifdef USE_CIRCLE_BRUSH
    float mouseDist = sqrt(pow(diffMouse.x, 2) + pow(diffMouse.y, 2));
    applyBrush = brushSize > 0 && mouseDist <= brushSize;
    #else
    applyBrush = brushSize > 0 && diffMouse.x <= brushSize && diffMouse.y <= brushSize;
    #endif // USE_CIRCLE_BRUSH
    
    if (applyBrush) {
        setCell(pos, getMaterialFromID(brushMaterial));
        //imageStore(output_light, pos, vec4(getMaterialFromID(brushMaterial).emission, 1.0));
        return;
    };

    update(pos);

    #ifdef DEBUG_SHOW_ORIG_POS
    imageStore(output_color, pos, vec4(vec2(getCell(pos).origPos) / vec2(input_size), 0.0, 1.0));
    #endif // DEBUG_SHOW_ORIG_POS
    
    #ifdef DEBUG_SHOW_MOVERIGHT
    vec3 col = vec3(1.0, 0.0, 0.0);
    if (moveRight) {
        col = vec3(0.0, 1.0, 0.0);
    }
    imageStore(output_color, pos, vec4(col, 1.0));
    #endif // DEBUG_SHOW_MOVERIGHT

    vec2 p = vec2(pos) / vec2(input_size);
    //imageStore(output_color, pos, vec4(p.x, p.y, 0.0, 1.0));
}