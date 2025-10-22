//Needs utils.glsl

#ifndef PI 
#define PI              3.1415926535897932384626433832795
#endif

// [ Duff et al. 2017, "Building an Orthonormal Basis, Revisited" ]
// Discontinuity at tangentZ.z == 0
mat3 getTangentBasis(vec3 tangentZ) {
    const float sign = tangentZ.z >= 0 ? 1.0 : -1.0;
    const float a = -1.0 / (sign + tangentZ.z);
    const float b = tangentZ.x * tangentZ.y * a;

    vec3 tangentX = vec3(1 + sign * a * pow2(tangentZ.x), sign * b, -sign * tangentZ.x);
    vec3 tangentY = vec3(b, sign + a * pow2(tangentZ.y), -tangentZ.y);

    return mat3(tangentX, tangentY, tangentZ);//HLSL ins trnasposed
}

// Reverse bits for uint (GLSL version of reversebits from HLSL)
uint reversebits(uint x) {
    // Reverse bit operations, standard bit-hack
    x = ((x & 0x55555555u) << 1) | ((x & 0xAAAAAAAAu) >> 1);
    x = ((x & 0x33333333u) << 2) | ((x & 0xCCCCCCCCu) >> 2);
    x = ((x & 0x0F0F0F0Fu) << 4) | ((x & 0xF0F0F0F0u) >> 4);
    x = ((x & 0x00FF00FFu) << 8) | ((x & 0xFF00FF00u) >> 8);
    x = (x << 16) | (x >> 16);
    return x;
}

vec2 hammersley(uint Index, uint NumSamples, uvec2 Random) {
    float E1 = fract(float(Index) / float(NumSamples) + float(Random.x & 0xffffu) / float(1u << 16));
    float E2 = float(reversebits(Index) ^ Random.y) * 2.3283064365386963e-10; // 1 / 2^32
    return vec2(E1, E2);
}

vec2 hammersley16(uint Index, uint NumSamples, uvec2 Random) {
    float E1 = fract(float(Index) / float(NumSamples) + float(Random.x) * (1.0 / 65536.0));
    float E2 = float((reversebits(Index) >> 16) ^ Random.y) * (1.0 / 65536.0);
    return vec2(E1, E2);
}

// http://extremelearning.com.au/a-simple-method-to-construct-isotropic-quasirandom-blue-noise-point-sequences/
vec2 R2Sequence(uint Index) {
    const float Phi = 1.324717957244746;
    const vec2 a = vec2(1.0 / Phi, 1.0 / (Phi * Phi));
    return fract(a * float(Index));
}

// ///////////////////////////////////////////////////////////////////////////////////////////////////
// /// WARPING
// ///////////////////////////////////////////////////////////////////////////////////////////////////

// PDF = 1 / (4 * PI)
vec4 uniformSampleSphere(vec2 E)
{
    float Phi = 2.0 * PI * E.x;
    float CosTheta = 1.0 - 2.0 * E.y;
    float SinTheta = sqrt(1.0 - CosTheta * CosTheta);

    vec3 H;
    H.x = SinTheta * cos(Phi);
    H.y = SinTheta * sin(Phi);
    H.z = CosTheta;

    float PDF = 1.0 / (4.0 * PI);

    return vec4(H, PDF);
}

// PDF = 1 / (2 * PI)
vec4 uniformSampleHemisphere(vec2 E)
{
    float Phi = 2.0 * PI * E.x;
    float CosTheta = E.y;
    float SinTheta = sqrt(1.0 - CosTheta * CosTheta);

    vec3 H;
    H.x = SinTheta * cos(Phi);
    H.y = SinTheta * sin(Phi);
    H.z = CosTheta;

    float PDF = 1.0 / (2.0 * PI);

    return vec4(H, PDF);
}

// PDF = NoL / PI
vec4 cosineSampleHemisphere(vec2 E)
{
    float Phi = 2.0 * PI * E.x;
    float CosTheta = sqrt(E.y);
    float SinTheta = sqrt(1.0 - CosTheta * CosTheta);

    vec3 H;
    H.x = SinTheta * cos(Phi);
    H.y = SinTheta * sin(Phi);
    H.z = CosTheta;

    float PDF = CosTheta * (1.0 / PI);

    return vec4(H, PDF);
}


// PDF = NoL / PI
vec4 cosineSampleHemisphere(vec2 E, vec3 N)
{
    vec3 H = uniformSampleSphere(E).xyz;
    H = normalize(N + H);  // Importance shift towards N

    float PDF = max(dot(H, N), 0.0) * (1.0 / PI); // safer than HLSL

    return vec4(H, PDF);
}

vec4 uniformSampleCone(vec2 E, float CosThetaMax)
{
    float Phi = 2.0 * PI * E.x;
    float CosTheta = mix(CosThetaMax, 1.0, E.y); // GLSL equivalent of lerp()
    float SinTheta = sqrt(1.0 - CosTheta * CosTheta);

    vec3 L;
    L.x = SinTheta * cos(Phi);
    L.y = SinTheta * sin(Phi);
    L.z = CosTheta;

    float PDF = 1.0 / (2.0 * PI * (1.0 - CosThetaMax));

    return vec4(L, PDF);
}
