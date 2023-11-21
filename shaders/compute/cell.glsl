


struct Cell {
    Material mat;
    ivec2 pos;
};

Cell newCell(Material mat, ivec2 pos) {
    return Cell(mat, pos);
}

struct RBCell {
    int matID;
    ivec2 orig_off;
    ivec2 pos;
    ivec2 prev_pos;
    int rb_idx;
};