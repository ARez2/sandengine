

//Make water look for sand above which it could swap to
bool canLiquidMoveHere(ivec2 pos, bool moveRight, bool includeHorizontal) {
    ivec2[3] neighs = {
        pos + UP,
        pos + UPLEFT,
        pos + UPRIGHT,
    };
    for (int n = 0; n < neighs.length(); n++) {
        Cell neigh = getCell(neighs[n]);
        if ((shouldDoMovSolidStep(neigh) && movSolidStep(neigh, moveRight, false) == pos) || isLiquid(neigh)) {
            return false;
        };
    };
    return true;
}

bool liquidMoveCondition(Cell liquid, ivec2 dir, int checkLength, bool moveRight, bool isMinor) {
    ivec2 checkpos = liquid.pos + dir * checkLength;
    Cell target = getCell(checkpos);
    if (target.mat.density >= liquid.mat.density) {
        return false;
    };

    // Had to implement a "priority"
    // Imagine this setup (moveRight=true):
    //             X  Y|
    // X thinks: "Since its moveRight, I have priority and
    //            should move right next to Y"
    // Y thinks: "Since I cannot move right, I can move left
    //            right next to X."
    // if both act, they would swap positions:
    //              YX |
    // This is not desired. Instead, X knows if it goes left 
    // as a minor (against the moveRight direction)

    // When it does it checks a certain amount of cells in the direction
    // it wants to move to and if there is a liquid, that could potentially
    // move, resulting in such a swap, X does not move
    if (isMinor) {
        for (int c = checkLength + 1; c < EMPTY_MAX_DISPERSION_CHECK; c++) {
            Cell ccell = getCell(liquid.pos + dir * c);
            if (ccell.mat.density < liquid.mat.density) {
                continue;
            }
            // Found a liquid that could move into or over our target position
            if (shouldDoLiquidStep(ccell) && ccell.pos.x - dir.x * ccell.mat.dispersion >= checkpos.x) {
                return false;
            }
        }
    }

    //return target.mat.density < liquid.mat.density;
    return canLiquidMoveHere(checkpos, moveRight, false);
}


// TODO: Apply liquid horizontal step between 2 liquids

ivec2 liquidStep(Cell self, bool moveRight, bool isSelf) {
    float ownDensity = self.mat.density;
    ivec2 pos = self.pos;

    ivec2[2] movepositions = getMoveDirs(pos + UP, moveRight);
    ivec2[3] positions1 = {
        pos + UP,
        movepositions[0],
        movepositions[1]
    };
    for (int p = 0; p < positions1.length(); p++) {
        ivec2 position = positions1[p];
        Cell target = getCell(position);
        if (shouldDoMovSolidStep(target) && movSolidStep(target, moveRight, false) == pos) {
            return position;
        }
    }

    ivec2 movSolidRes = movSolidStep(self, moveRight, isSelf);
    if (movSolidRes != pos) {
        return movSolidRes;
    };

    ivec2[2] positions = getMoveDirs(moveRight);
    
    int dispersion = self.mat.dispersion;
    ivec2 last_possible_pos = pos;
    for (int disp = 1; disp <= dispersion; disp++) {
        if (liquidMoveCondition(self, positions[0], disp, moveRight, false)) {
            last_possible_pos = pos + positions[0] * disp;
        } else if (liquidMoveCondition(self, positions[1], disp, moveRight, true)) {
            last_possible_pos = pos + positions[1] * disp;
        } else {
            break;
        };
    };

    return last_possible_pos;
}