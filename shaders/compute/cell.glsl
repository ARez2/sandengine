


struct Cell {
    Material mat;
    ivec2 pos;
};

Cell newCell(Material mat, ivec2 pos) {
    return Cell(mat, pos);
}

struct RBCell {
    int matID;
    ivec2 orig_pos;
    ivec2 pos;
    int rb_idx;
};