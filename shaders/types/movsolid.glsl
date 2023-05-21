

ivec2 movSolidStep(Cell self, bool moveRight) {
    float ownDensity = self.mat.density;
    ivec2 pos = self.pos;

    if (getCell(pos + DOWN).mat.density < ownDensity) {
        return pos + DOWN;
    };

    ivec2[2] positions = getMoveDirs(pos + DOWN, moveRight);
    int len = positions.length();
    for (int p = 1; p < len; p++) {
        Cell target = getCell(positions[p]);
        Cell above_target = getCell(target.pos + UP);
        if (target.mat.density < ownDensity && (!shouldDoMovSolidStep(above_target) || above_target.mat.density < ownDensity || above_target.mat.density < target.mat.density)) {
            return positions[p];
        };
    }

    return pos;
}