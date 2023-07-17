


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
    return cell.mat.emission == vec3(0.0) && (isSolid(cell) || isMovSolid(cell));
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