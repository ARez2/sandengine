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


bool isCollider(Cell cell) {
    return cell.mat != EMPTY;// && !isGas(cell) && !isLiquid(cell)
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

    ivec2[8] neighpos = getDiagonalNeighbours(pos, true);
    float[8] neighs = float[8](
        float(isCollider(getCell(neighpos[0]))),
        float(isCollider(getCell(neighpos[1]))),
        float(isCollider(getCell(neighpos[2]))),
        float(isCollider(getCell(neighpos[3]))),
        float(isCollider(getCell(neighpos[4]))),
        float(isCollider(getCell(neighpos[5]))),
        float(isCollider(getCell(neighpos[6]))),
        float(isCollider(getCell(neighpos[7]))),
        );
    float gx =    (1.0 * neighs[2]) +         0         + (-1.0 * neighs[1])
                + (2.0 * neighs[4]) +         0         + (-2.0 * neighs[3])
                + (1.0 * neighs[6]) +         0         + (-1.0 * neighs[7]);
    
    float gy =    (1.0 * neighs[2]) + (2.0 * neighs[0]) + (1.0 * neighs[1])
                +         0         +         0         +        0
                +(-1.0 * neighs[6]) +(-2.0 * neighs[5]) +(-1.0 * neighs[7]);
    
    float g = sqrt(pow(gx, 2.0) + pow(gy, 2.0));
    if (neighs[0] > 0.0) { 
        imageStore(collision_data, pos, vec4(vec3(1.0), 1.0));
    } else {
        imageStore(collision_data, pos, vec4(vec3(0.0), 1.0));
    }

    // if (
    //     // Diagonal backslash
    //     (isCollider(getCell(pos, UPLEFT)) && isCollider(getCell(pos, DOWNRIGHT)))
    //     // Diagonal /
    //      || (isCollider(getCell(pos, UPRIGHT)) && isCollider(getCell(pos, DOWNLEFT)))
    //     // Horizontal -
    //      || (isCollider(getCell(pos, LEFT)) && isCollider(getCell(pos, RIGHT)))
    //     // Vertical |
    //      || (isCollider(getCell(pos, UP)) && isCollider(getCell(pos, DOWN)))
    //     // Vertical Edge |_
    //      || (isCollider(getCell(pos, UP)) && (isCollider(getCell(pos, DOWNRIGHT)) || isCollider(getCell(pos, DOWNLEFT))))
    //      || (isCollider(getCell(pos, DOWN)) && (isCollider(getCell(pos, UPRIGHT)) || isCollider(getCell(pos, UPLEFT))))
    //     // Horizontal Edge 
    //      || (isCollider(getCell(pos, LEFT)) && (isCollider(getCell(pos, UPRIGHT)) || isCollider(getCell(pos, DOWNRIGHT))))
    //      || (isCollider(getCell(pos, RIGHT)) && (isCollider(getCell(pos, UPLEFT)) || isCollider(getCell(pos, DOWNLEFT))))
    //      ) {
    //     imageStore(collision_data, pos, vec4(vec3(1.0), 1.0));
    // } else {
    //     imageStore(collision_data, pos, vec4(vec3(0.0), 1.0));
    // }
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