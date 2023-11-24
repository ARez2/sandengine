


struct Cell {
    Material mat;
    ivec2 pos;
};

Cell newCell(Material mat, ivec2 pos) {
    return Cell(mat, pos);
}