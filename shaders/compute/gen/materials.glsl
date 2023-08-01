struct Material {
    int id;
    vec4 color;
    float density;
    vec4 emission;

    int type;
};
#define TYPE_movable_solid 0
#define TYPE_solid 1
#define MAT_sand Material(0, vec4(0.003921569, 0.003921569, 0.003921569, 1), 1.5, vec4(0, 0, 0, 0), TYPE_movable_solid)
#define MAT_glowy_rock Material(1, vec4(0.196, 0.55, 0.184, 1), 3, vec4(0, 0.8, 0.1, 1), TYPE_solid)
