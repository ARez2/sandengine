

#define TYPE_EMPTY 0
void random_func() {

}
#define TYPE_SOLID 1
#define TYPE_MOVSOLID 2
#define TYPE_LIQUID 3
#define TYPE_GAS 4
#define TYPE_PLANT 5

#define EMPTY Material(0, vec4(0.0, 0.0, 0.0, 0.0), 1.0,  vec4(0.0), TYPE_EMPTY)
#define SAND  Material(1, vec4(1.0, 1.0, 0.0, 1.0), 3.0,  vec4(0.0), TYPE_MOVSOLID)
#define SOLID Material(2, vec4(0.4, 0.4, 0.4, 1.0), 4.0,  vec4(0.0), TYPE_SOLID)
#define WATER Material(3, vec4(0.0, 0.0, 1.0, 0.5), 2.0,  vec4(0.0), TYPE_LIQUID)
#define NULL  Material(4, vec4(1.0, 0.0, 1.0, 1.0), 0.0,  vec4(0.0), TYPE_EMPTY)
#define WALL  Material(5, vec4(0.1, 0.1, 0.1, 1.0), 99.0, vec4(0.0), TYPE_SOLID)

#define RADIOACTIVE Material(6, vec4(0.196, 0.55, 0.184, 1.0), 5.0, vec4(0.05, 0.7, 0.05, 0.9), TYPE_SOLID)
#define SMOKE Material(7, vec4(0.3, 0.3, 0.3, 0.3), 0.1, vec4(0.0), TYPE_GAS)
#define TOXIC Material(8, vec4(0.0, 0.7, 0.2, 0.5), 1.8, vec4(0.0, 0.5, 0.0, 0.99999), TYPE_LIQUID)

#define VINE Material(9, vec4(0.14, 0.5, 0.19, 1.0), 2.5, vec4(0.0), TYPE_PLANT)