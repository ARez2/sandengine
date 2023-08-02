
// ======== MANDATORY, DEFAULT MATERIALS AND TYPES, DONT CHANGE ========
#define TYPE_NULL 0
#define TYPE_WALL 1
#define TYPE_EMPTY 2
#define MAT_NULL Material(0, vec4(1.0, 0.0, 1.0, 1.0), 0.0,  vec4(0.0), TYPE_NULL)
#define MAT_WALL Material(1, vec4(0.1, 0.1, 0.1, 1.0), 9999.0, vec4(0.0), TYPE_WALL)
#define MAT_EMPTY Material(2, vec4(0.0), 1.0, vec4(0.0), TYPE_EMPTY)

// =====================================================================

#define TYPE_solid 3

bool isType_solid(Cell cell) {
    return cell.mat.type == TYPE_solid;
}

#define TYPE_movable_solid 4

bool isType_movable_solid(Cell cell) {
    return cell.mat.type == TYPE_movable_solid;
}

#define TYPE_liquid 5

bool isType_liquid(Cell cell) {
    return cell.mat.type == TYPE_liquid;
}

#define TYPE_gas 6

bool isType_gas(Cell cell) {
    return cell.mat.type == TYPE_gas;
}

#define TYPE_plant 7

bool isType_plant(Cell cell) {
    return cell.mat.type == TYPE_plant;
}


#define MAT_sand Material(3, vec4(1, 1, 0, 1), 1.5, vec4(0, 0, 0, 0), TYPE_movable_solid)
#define MAT_rock Material(4, vec4(0.4, 0.4, 0.4, 1), 4, vec4(0, 0, 0, 0), TYPE_solid)
#define MAT_water Material(5, vec4(0, 0, 1, 0.5), 1.5, vec4(0, 0, 0, 0), TYPE_liquid)
#define MAT_radioactive Material(6, vec4(0.196, 0.55, 0.184, 1), 5, vec4(0.05, 0.7, 0.05, 0.9), TYPE_solid)
#define MAT_smoke Material(7, vec4(0.3, 0.3, 0.3, 0.3), 0.1, vec4(0, 0, 0, 0), TYPE_gas)
#define MAT_toxic_sludge Material(8, vec4(0, 0.7, 0.2, 0.5), 1.8, vec4(0, 0.5, 0, 0.99999), TYPE_liquid)

Material[6] materials() {
    Material allMaterials[6] = {
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

