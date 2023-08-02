


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
        return newCell(MAT_WALL, pos);
        #endif // SCREEN_IS_BORDER
        return newCell(MAT_NULL, pos);
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
    return cell.mat != MAT_EMPTY && cell.mat != MAT_NULL && cell.mat != MAT_WALL;// && !isGas(cell) && !isLiquid(cell)
}

// bool isLightObstacle(Cell cell) {
//     return cell.mat.emission.rgb == vec3(0.0) && (isSolid(cell) || isMovSolid(cell));
// }


bool gt(vec3 a, vec3 b) {
    return a.x > b.x && a.y > b.y && a.z > b.z;
}

void setCell(ivec2 pos, Cell cell, bool setCollision) {
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

    int numColliders = int(isCollider(neighCells[3])) + int(isCollider(neighCells[4])) + int(isCollider(neighCells[0])) + int(isCollider(neighCells[5]));
    if (setCollision && isCollider(cell) && numColliders < 4) {
        imageStore(collision_data, pos / 8, max(imageLoad(collision_data, pos / 8), vec4(vec3(1.0), 0.1)));
    }
    
    vec4 ambientLight = vec4(vec3(0.3), 1.0);
    vec4 light;
    // if (cell.mat.emission.rgb != vec3(0.0)) {
    //     light = cell.mat.emission;
    // } else if (pos.y == 0) {
    //     light = vec4(vec3(1.0), 0.9999999);
    // } else {
    //     vec3 avg_light = vec3(0.0);
    //     vec3 max_light = vec3(0.0);
    //     float avg_falloff = 0.0;
    //     int num_falloff = 0;

    //     int num_lightsources = 0;
    //     for (int n = 0; n < neighs.length(); n++) {
    //         Cell neigh = neighCells[n];
    //         ivec2 neighPos = neigh.pos;
    //         bool neighObstacle = isLightObstacle(neigh);
    //         vec4 light_data = texelFetch(input_light, neighPos, 0) * vec4(vec3(float(!neighObstacle)), 1.0);
    //         if ((gt(light_data.rgb, vec3(0.0)) && light_data.a > 0.0) || neigh.mat == MAT_EMPTY) {
    //             num_lightsources += 1;
    //             vec3 light = light_data.rgb * light_data.a * (1/length(light_data.rgb));
    //             avg_light += light;
    //             if (light_data.a > 0.0) {
    //                 avg_falloff += light_data.a;
    //                 num_falloff += 1;
    //             }

    //             //               0.96, (light_data.a - (1.0 - light_data.a) * 100.0)
    //             vec3 m = light * (light_data.a * 0.9);
    //             max_light = max(max_light, m);
    //         }
            
    //     }
    //     if (num_lightsources > 0) {
    //         avg_light /= num_lightsources;
    //     }
    //     if (num_falloff> 0) {
    //         avg_falloff /= float(num_falloff);
    //     }
    //     // Max light is fast but produces star like patterns and average is too slow, so lerp
    //     //                                     0.1, 0.25
    //     light = vec4(mix(avg_light.rgb, max_light, 0.25), avg_falloff);
        
    // }
    // imageStore(output_light, pos, light);
    
    // if (cell.mat == EMPTY) {
    //     //imageStore(output_color, pos, light);
    //     imageStore(output_color, pos, color * min(light + ambientLight, vec4(1.0)));
    // } else {
    //     imageStore(output_color, pos, color * min(light + ambientLight, vec4(1.0)));
    // }
    imageStore(output_color, pos, color);
}
void setCell(ivec2 pos, Material mat, bool setCollision) {
    setCell(pos, newCell(mat, pos), setCollision);
}
