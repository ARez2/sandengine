#define TYPE_EMPTY 0

#define TYPE_NULL 1

#define TYPE_WALL 2

#define TYPE_solid 3

#define TYPE_movable_solid 4

#define TYPE_liquid 5

#define TYPE_gas 6

#define TYPE_plant 7

bool isType_EMPTY(Cell cell) {
    return cell.mat.type == TYPE_EMPTY;
}

bool isType_NULL(Cell cell) {
    return cell.mat.type == TYPE_NULL;
}

bool isType_WALL(Cell cell) {
    return cell.mat.type == TYPE_WALL;
}

bool isType_solid(Cell cell) {
    return cell.mat.type == TYPE_solid || cell.mat.type == TYPE_movable_solid;
}

bool isType_movable_solid(Cell cell) {
    return cell.mat.type == TYPE_movable_solid;
}

bool isType_liquid(Cell cell) {
    return cell.mat.type == TYPE_liquid;
}

bool isType_gas(Cell cell) {
    return cell.mat.type == TYPE_gas;
}

bool isType_plant(Cell cell) {
    return cell.mat.type == TYPE_plant;
}


#define MAT_EMPTY Material(0, vec4(0, 0, 0, 0), 1, vec4(0, 0, 0, 0), TYPE_EMPTY)
#define MAT_NULL Material(1, vec4(1, 0, 1, 1), 0, vec4(0, 0, 0, 0), TYPE_NULL)
#define MAT_WALL Material(2, vec4(0.1, 0.2, 0.3, 1), 9999, vec4(0, 0, 0, 0), TYPE_WALL)
#define MAT_sand Material(3, vec4(1, 1, 0, 1), 1.5, vec4(0, 0, 0, 0), TYPE_movable_solid)
#define MAT_rock Material(4, vec4(0.4, 0.4, 0.4, 1), 4, vec4(0, 0, 0, 0), TYPE_solid)
#define MAT_water Material(5, vec4(0, 0, 1, 0.5), 1.5, vec4(0, 0, 0, 0), TYPE_liquid)
#define MAT_radioactive Material(6, vec4(0.196, 0.55, 0.184, 1), 5, vec4(0.05, 0.7, 0.05, 0.9), TYPE_solid)
#define MAT_smoke Material(7, vec4(0.3, 0.3, 0.3, 0.3), 0.1, vec4(0, 0, 0, 0), TYPE_gas)
#define MAT_toxic_sludge Material(8, vec4(0, 0.7, 0.2, 0.5), 1.8, vec4(0, 0.5, 0, 0.99999), TYPE_liquid)

Material[9] materials() {
    Material allMaterials[9] = {
        MAT_EMPTY,
MAT_NULL,
MAT_WALL,
MAT_sand,
MAT_rock,
MAT_water,
MAT_radioactive,
MAT_smoke,
MAT_toxic_sludge,

    };
    return allMaterials;
}

Material getMaterialFromID(int id) {
    for (int i = 0; i < materials().length(); i++) {
        if (id == materials()[i].id) {
            return materials()[i];
        };
    };
    return MAT_NULL;
}

