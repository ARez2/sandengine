bool outOfBounds(vec2 pos) {
    return pos.x >= simSize.x || pos.x < 0 || pos.y >= simSize.y || pos.y < 0;
}
bool outOfBounds(ivec2 pos) {
    return pos.x >= simSize.x || pos.x < 0 || pos.y >= simSize.y || pos.y < 0;
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
    return cell.mat != EMPTY;// && !isGas(cell) && !isLiquid(cell)
}

bool isLightObstacle(Cell cell) {
    return cell.mat.emission == vec3(0.0) && (isSolid(cell) || isMovSolid(cell));
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
    
    vec4 light;
    if (cell.mat.emission != vec3(0.0)) {
        light = vec4(cell.mat.emission, 1.0);
    } else {
        ivec2[8] neighs = getDiagonalNeighbours(pos, moveRight);
        vec3 avg_light = vec3(0.0);
        vec3 max_light = vec3(0.0);
        vec2 offsetsToLight = vec2(0.0);
        
        int num_lightsources = 0;
        for (int n = 0; n < neighs.length(); n++) {
            ivec2 neighPos = neighs[n];
            Cell neigh = getCell(neighPos);
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
        light = vec4(mix(avg_light, max_light, 0.1), 1.0);
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
void setCell(ivec2 pos, Material mat) {
    setCell(pos, Cell(mat, pos, pos));
}


// Copies the data from another position to this position
void pullCell(ivec2 from, ivec2 to) {
    Cell other = getCell(from);
    if (isSolid(other)) {
        setCell(to, EMPTY);
    } else {
        setCell(to, other);
    }
}