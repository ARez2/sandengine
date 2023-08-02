struct Material {
    int id;
    vec4 color;
    float density;
    vec4 emission;

    int type;
};
#define TYPE_empty 0
#define TYPE_solid 1
#define TYPE_movable_solid 2
#define TYPE_liquid 3
#define TYPE_gas 4
#define TYPE_plant 5
#define TYPE_type0 6
#define TYPE_type1 7
#define TYPE_type2 8

#define MAT_empty Material(0, vec4(0, 0, 0, 0), 1, vec4(0, 0, 0, 0), TYPE_empty)
#define MAT_sand Material(1, vec4(0.003921569, 0.003921569, 0.003921569, 1), 1.5, vec4(0, 0, 0, 0), TYPE_movable_solid)
#define MAT_rock Material(2, vec4(0.4, 0.4, 0.4, 1), 4, vec4(0, 0, 0, 0), TYPE_solid)
#define MAT_water Material(3, vec4(0, 0, 1, 0.5), 1.5, vec4(0, 0, 0, 0), TYPE_liquid)
#define MAT_radioactive Material(4, vec4(0.196, 0.55, 0.184, 1), 5, vec4(0.05, 0.7, 0.05, 0.9), TYPE_solid)
#define MAT_smoke Material(5, vec4(0.3, 0.3, 0.3, 0.3), 0.1, vec4(0, 0, 0, 0), TYPE_gas)
#define MAT_toxic_sludge Material(6, vec4(0, 0.7, 0.2, 0.5), 1.8, vec4(0, 0.5, 0, 0.99999), TYPE_liquid)
#define MAT_vine Material(7, vec4(0.14, 0.5, 0.19, 1), 2.5, vec4(0, 0, 0, 0), TYPE_plant)
