


struct Cell {
    Material mat;
    ivec2 pos;
    int rb_idx;
    ivec2 prev_pos;
};

Cell newCell(Material mat, ivec2 pos) {
    return Cell(mat, pos, -1, pos);
}

Cell newCell(Material mat, ivec2 pos, ivec2 prev_pos) {
    return Cell(mat, pos, -1, prev_pos);
}