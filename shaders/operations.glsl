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