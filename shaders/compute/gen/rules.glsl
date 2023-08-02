
// =============== RULES ===============
void rule_gravity (inout Cell SELF, inout Cell RIGHT, inout Cell DOWN, inout Cell DOWNRIGHT, ivec2 pos) {
    // If the precondition isnt met, return
    if (!isType_movable_solid(SELF) || isType_type0(SELF)) {
        return;
    }

    if (DOWN.mat.density < SELF.mat.density) {
        swap(SELF, DOWN);
SELF = setCell(vine, pos);
    }
}

void rule_slide_diagonally (inout Cell SELF, inout Cell RIGHT, inout Cell DOWN, inout Cell DOWNRIGHT, ivec2 pos) {
    // If the precondition isnt met, return
    if (!isType_movable_solid(SELF) || isType_type1(SELF)) {
        return;
    }

    if (RIGHT.mat.density < SELF.mat.density || DOWNRIGHT.mat.density < SELF.mat.density) {
        swap(SELF, DOWNRIGHT);
    }
}

void rule_slide_left (inout Cell SELF, inout Cell RIGHT, inout Cell DOWN, inout Cell DOWNRIGHT, ivec2 pos) {
    // If the precondition isnt met, return
    if (!isType_type2(SELF)) {
        return;
    }

    if (LEFT.mat.density < SELF.mat.density) {
        swap(SELF, LEFT);
    }
}

void rule_vine_rule (inout Cell SELF, inout Cell RIGHT, inout Cell DOWN, inout Cell DOWNRIGHT, ivec2 pos) {
    // If the precondition isnt met, return
    if (!SELF.mat == MAT_vine) {
        return;
    }

    if (SELF.mat == empty && DOWN.mat == vine) {
        SELF = setCell(vine, pos);
    }
}




// =============== CALLERS ===============
void applyMirroredRules(
    inout Cell SELF,
    inout Cell RIGHT,
    inout Cell DOWN,
    inout Cell DOWNRIGHT,
    ivec2 pos) {
    rule_slide_diagonally(SELF, RIGHT, DOWN, DOWNRIGHT, pos);
}


void applyLeftRules(
    inout Cell SELF,
    inout Cell LEFT,
    inout Cell DOWN,
    inout Cell DOWNLEFT,
    ivec2 pos) {
    rule_slide_left(SELF, LEFT, DOWN, DOWNRIGHT, pos);
}

void applyRightRules(
    inout Cell SELF,
    inout Cell RIGHT,
    inout Cell DOWN,
    inout Cell DOWNRIGHT,
    ivec2 pos) {
    rule_gravity(SELF, RIGHT, DOWN, DOWNRIGHT, pos);
rule_vine_rule(SELF, RIGHT, DOWN, DOWNRIGHT, pos);
}