

ivec2 gasStep(Cell self, bool moveRight, bool isSelf) {
    float ownDensity = self.mat.density;
    ivec2 pos = self.pos;


    Cell above;
    Cell left;
    Cell right;
    Cell upleft;
    Cell upright;
    if (isSelf) {
        above = neighbours[NEIGH_IDX_UP];
        left = neighbours[NEIGH_IDX_LEFT];
        right = neighbours[NEIGH_IDX_RIGHT];
        upleft = neighbours[NEIGH_IDX_UPLEFT];
        upright = neighbours[NEIGH_IDX_UPRIGHT];
    } else {
        above = getCell(pos + UP);
        left = getCell(pos + LEFT);
        right = getCell(pos + RIGHT);
        upleft = getCell(pos + UPLEFT);
        upright = getCell(pos + UPRIGHT);
    }
    bool canMoveUp = ownDensity < above.mat.density && !isSolid(above)
        && (!shouldDoGasStep(left) || (left.mat.density < upleft.mat.density || left.mat.density >= above.mat.density || left.mat.density < getCell(left.pos + UPLEFT).mat.density))
        && (!shouldDoGasStep(right) || (right.mat.density < upright.mat.density || right.mat.density >= above.mat.density || right.mat.density < getCell(right.pos + UPRIGHT).mat.density));
    if (canMoveUp) {
        return pos + UP;
    };


    Cell firstTarget;
    Cell secondTarget;
    if (moveRight) {
        firstTarget = upright;
        secondTarget = upleft;
    } else {
        firstTarget = upleft;
        secondTarget = upright;
    }

    if (ownDensity < firstTarget.mat.density && (firstTarget.mat == EMPTY || isGas(firstTarget))) {
        return firstTarget.pos;
    }

    if (ownDensity < secondTarget.mat.density && (secondTarget.mat == EMPTY || isGas(secondTarget))) {
        return secondTarget.pos;
    }

    return pos;
}