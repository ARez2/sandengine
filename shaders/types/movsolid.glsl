

ivec2 movSolidStep(Cell self, bool moveRight, bool isSelf) {
    float ownDensity = self.mat.density;
    ivec2 pos = self.pos;

    // TODO: Check if downright/ -left is Liquid and wants to move horizontally
    Cell below;
    Cell left;
    Cell right;
    Cell downleft;
    Cell downright;
    if (isSelf) {
        below = neighbours[NEIGH_IDX_DOWN];
        left = neighbours[NEIGH_IDX_LEFT];
        right = neighbours[NEIGH_IDX_RIGHT];
        downleft = neighbours[NEIGH_IDX_DOWNLEFT];
        downright = neighbours[NEIGH_IDX_DOWNRIGHT];
    } else {
        below = getCell(pos + DOWN);
        left = getCell(pos + LEFT);
        right = getCell(pos + RIGHT);
        downleft = getCell(pos + DOWNLEFT);
        downright = getCell(pos + DOWNRIGHT);
    }
    bool canMoveDown = below.mat.density < ownDensity
        && (!shouldDoMovSolidStep(left) || (left.mat.density > downleft.mat.density || left.mat.density <= below.mat.density || left.mat.density > getCell(left.pos + DOWNLEFT).mat.density))
        && (!shouldDoMovSolidStep(right) || (right.mat.density > downright.mat.density || right.mat.density <= below.mat.density || right.mat.density > getCell(right.pos + DOWNRIGHT).mat.density));
    if (canMoveDown) {
        return pos + DOWN;
    };

    Cell firstTarget;
    Cell secondTarget;
    if (moveRight) {
        firstTarget = downright;
        secondTarget = downleft;
    } else {
        firstTarget = downleft;
        secondTarget = downright;
    }
    
    if (firstTarget.mat.density < ownDensity) {
        return firstTarget.pos;
    }

    if (secondTarget.mat.density < ownDensity) {
        return secondTarget.pos;
    }

    return pos;
}