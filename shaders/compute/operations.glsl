


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
    int rb_idx = int(data.g);
    ivec2 prev_pos = ivec2(data.b, data.a);

    return Cell(getMaterialFromID(matID), pos, rb_idx, prev_pos);
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
    ivec4 data = ivec4(cell.mat.id, cell.rb_idx, cell.prev_pos.x, cell.prev_pos.y);
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
