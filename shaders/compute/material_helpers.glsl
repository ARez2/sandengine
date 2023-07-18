#define NUM_MATERIALS 10

Material[NUM_MATERIALS] materials() {
    Material allMaterials[NUM_MATERIALS] = {
        EMPTY,
        SAND,
        SOLID,
        WATER,
        NULL,
        WALL,
        RADIOACTIVE,
        SMOKE,
        TOXIC,
        VINE,
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

bool isEmpty(Cell cell) {
    return cell.mat == EMPTY;
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

bool isPlant(Cell cell) {
    return cell.mat.type == TYPE_PLANT;
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