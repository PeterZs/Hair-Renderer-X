/*
Spherical Harmonics Utility Encoding functions
*/

//////////////////////////
//Level 1
//////////////////////////
void encodeScalarValueToL1SH(float x, vec3 dir, out float sh[4]) {

    const float Y_0_0 = 0.282095;
    const float Y_minus1_1 = 0.488603 * dir.y;
    const float Y_0_1 = 0.488603 * dir.z;
    const float Y_1_1 = 0.488603 * dir.x;

    sh[0] += x * Y_0_0;
    sh[1] += x * Y_minus1_1;
    sh[2] += x * Y_0_1;
    sh[3] += x * Y_1_1;
}
float decodeScalarValueFromL1SH(vec4 sh, vec3 dir){
    return dot(sh, vec4(0.282095, 0.488603 * dir.y, 0.488603 * dir.z, 0.488603 * dir.x));
}
//////////////////////////
//Level 2 
//////////////////////////

// ....
