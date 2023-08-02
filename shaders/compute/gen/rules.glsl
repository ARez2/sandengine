
// =============== RULES ===============
void rule_fall_slide (inout Cell self, inout Cell right, inout Cell down, inout Cell downright, ivec2 pos) {
    // If the precondition isnt met, return
    if (!(isType_movable_solid(self))) {
        return;
    }

    if (down.mat.density < self.mat.density) {
    swap(self, down);
} else {
    
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