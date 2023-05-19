#version 430
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout(std140) buffer MyBlock {
    float power;
    vec4 values[4096/4];
};
void main() {
    vec4 val = values[gl_GlobalInvocationID.x];
    values[gl_GlobalInvocationID.x] = pow(val, vec4(power));
}