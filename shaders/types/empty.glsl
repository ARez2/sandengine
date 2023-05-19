

bool tryPullMovSolid(Cell self, bool moveRight) {
    ivec2[2] movePositions = getMoveDirs(self.pos + UP, moveRight);
    ivec2[3] positions = {
        self.pos + UP,
        movePositions[0],
        movePositions[1]
    };

    for (int p = 0; p < positions.length(); p++) {
        Cell c = getCell(positions[p]);
        if (shouldDoMovSolidStep(c) && movSolidStep(c, moveRight) == self.pos) {
            pullCell(positions[p], self.pos);
            return true;
        }
    }
    return false;
}


bool tryPullGas(Cell self, bool moveRight) {
    ivec2[2] movePositions = getMoveDirs(self.pos + DOWN, moveRight);
    ivec2[3] positions = {
        self.pos + DOWN,
        movePositions[0],
        movePositions[1]
    };

    for (int p = 0; p < positions.length(); p++) {
        Cell c = getCell(positions[p]);
        if (shouldDoGasStep(c) && gasStep(c, moveRight) == self.pos) {
            pullCell(positions[p], self.pos);
            return true;
        }
    }
    return false;
}


void emptyStep(Cell self, bool moveRight) {
    ivec2 pos = self.pos;
    
    if (tryPullMovSolid(self, moveRight)) {
        return;
    }
    
    ivec2[2] positions = getMoveDirs(moveRight);
    int dispersion = EMPTY_MAX_DISPERSION_CHECK;
    ivec2 last_possible_pos = pos;
    // Horizontal, account for dispersion
    for (int disp = dispersion; disp > 0; disp--) {
        ivec2 first_checkpos = pos + positions[0] * disp;
        ivec2 second_checkpos = pos + positions[1] * disp;
        Cell first = getCell(first_checkpos);
        Cell second = getCell(second_checkpos);
        if (isLiquid(first) && liquidStep(first, moveRight) == pos) {
            pullCell(first_checkpos, pos);
            return;
        }
        if (isLiquid(second) && liquidStep(second, moveRight) == pos) {
            pullCell(second_checkpos, pos);
            return;
        };
    };

    ivec2[2] movepositions = getMoveDirs(pos + DOWN, moveRight);
    ivec2[3] positions2 = {
        pos + DOWN,
        movepositions[0],
        movepositions[1]
    };
    for (int p = 0; p < positions2.length(); p++) {
        ivec2 position = positions2[p];
        Cell target = getCell(position);
        if (shouldDoLiquidStep(target) && liquidStep(target, moveRight) == pos) {
            pullCell(position, pos);
            return;
        }
    }

    if (tryPullGas(self, moveRight)) {
        return;
    }

    setCell(pos, self);
}