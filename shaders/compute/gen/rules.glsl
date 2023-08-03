
// =============== RULES ===============
void rule_fall_slide (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, ivec2 pos) {
    // If the precondition isnt met, return
    if (!(isType_movable_solid(self) || isType_liquid(self))) {
        return;
    }

    if (down.mat.density < self.mat.density) {
    swap(self, down);
} else {
    if (right.mat.density < self.mat.density && downright.mat.density < self.mat.density) {
    swap(self, downright);
} else {
    
}
}
}

void rule_horizontal_slide (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, ivec2 pos) {
    // If the precondition isnt met, return
    if (!(isType_liquid(self))) {
        return;
    }

    if (right.mat.density < self.mat.density) {
    swap(self, right);
} else {
    if (downright.mat.density < down.mat.density) {
    swap(down, downright);
} else {
    
}
}
}




// =============== CALLERS ===============
void applyMirroredRules(
    inout Cell self,
    inout Cell right,
    inout Cell down,
    inout Cell downright,
    ivec2 pos) {
    rule_fall_slide(self, right, down, downright, pos);
rule_horizontal_slide(self, right, down, downright, pos);
}


void applyLeftRules(
    inout Cell self,
    inout Cell right,
    inout Cell down,
    inout Cell downright,
    ivec2 pos) {
    
}

void applyRightRules(
    inout Cell self,
    inout Cell right,
    inout Cell down,
    inout Cell downright,
    ivec2 pos) {
    
}