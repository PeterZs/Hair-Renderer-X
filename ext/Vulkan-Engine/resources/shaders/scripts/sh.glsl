/*Spherical armonics utility functions*/

//Level 1 Spherical Armonic
vec4 encodeScalarToSHL1(in float scalar, in vec3 dir ) {
    const float sh0 = 0.282095;              // Y₀₀ (constant)
    const float sh1 = 0.488603 * dir.y;      // Y₁₋₁
    const float sh2 = 0.488603 * dir.z;      // Y₁₀
    const float sh3 = 0.488603 * dir.x;      // Y₁₁

    // Encode scalar into each SH coefficient
    vec4 sh;
    sh[0] = scalar * sh0;
    sh[1] = scalar * sh1;
    sh[2] = scalar * sh2;
    sh[3] = scalar * sh3;

    return sh;
}

float decodeScalarFromSHL1(vec4 shl1, vec3 dir){
    return dot(shl1, vec4(0.282095, 0.488603 * dir.y, 0.488603 * dir.z, 0.488603 * dir.x));
}


//Level 2 Spherical Armonic