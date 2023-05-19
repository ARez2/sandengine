

Material[9] materials() {
    Material allMaterials[9] = {
        EMPTY,
        SAND,
        SOLID,
        WATER,
        NULL,
        WALL,
        RADIOACTIVE,
        SMOKE,
        TOXIC,
    };
    return allMaterials;
}

Material getMaterialFromID(int id) {
    for (int i = 0; i < materials().length(); i++) {
        if (id == materials()[i].id) {
            return materials()[i];
        };
    };
    return NULL;
}

bool isSolid(Cell cell) {
    return cell.mat.type == TYPE_SOLID;
}

bool isLiquid(Cell cell) {
    return cell.mat.type == TYPE_LIQUID;
}

bool isGas(Cell cell) {
    return cell.mat.type == TYPE_GAS;
}

bool isMovSolid(Material mat) {
    return mat.type == TYPE_MOVSOLID;
}
bool isMovSolid(Cell cell) {
    return cell.mat.type == TYPE_MOVSOLID;
}


bool shouldDoMovSolidStep(Cell cell) {
    return isMovSolid(cell) || isLiquid(cell);
}
bool shouldDoLiquidStep(Cell cell) {
    return isLiquid(cell);
}
bool shouldDoGasStep(Cell cell) {
    return isGas(cell);
}