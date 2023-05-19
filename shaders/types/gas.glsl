

ivec2 gasStep(Cell self, bool moveRight) {
    float ownDensity = self.mat.density;
    ivec2 pos = self.pos;

    Cell above = getCell(pos + UP);
    if (ownDensity < above.mat.density && !isSolid(above)) {
        return pos + UP;
    };

    ivec2[2] positions = getMoveDirs(pos + UP, moveRight);
    for (int p = 1; p < positions.length(); p++) {
        Cell target = getCell(positions[p]);
        Cell below_target = getCell(target.pos + DOWN);
        if (ownDensity < target.mat.density && !isSolid(target) && (!(shouldDoGasStep(below_target)) || below_target.mat.density > ownDensity || below_target.mat.density > target.mat.density)) {
            return positions[p];
        };
    }

    return pos;
}