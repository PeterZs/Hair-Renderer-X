#shader compute
#version 460
#include BRDFs/disney_hair_BSDF.glsl

layout(local_size_x = 16, local_size_y = 16, local_size_z = 16) in;

layout(rgba32f, set = 0, binding = 0) uniform writeonly image2D outputFrontAtt;
layout(rgba32f, set = 0, binding = 1) uniform writeonly image2D outputBackAtt;
layout(set = 0, binding = 2) uniform sampler3D DpTex;
layout(rgba32f, set = 0, binding = 5) uniform writeonly image2D outputFrontShifts;
layout(rgba32f, set = 0, binding = 6) uniform writeonly image2D outputBackShifts;
layout(rgba32f, set = 0, binding = 7) uniform writeonly image2D outputFrontBetas;
layout(rgba32f, set = 0, binding = 8) uniform writeonly image2D outputBackBetas;
layout(set = 0, binding = 9) buffer BSDFIntegralBuffer {
    vec4 normIntegral;
};


layout(set = 1, binding = 1) uniform MaterialUniforms {
    vec3 Cr;
    float Ir;

    vec3 Ctt;
    float Itt;

    vec3 Ctrt;
    float Itrt;

    vec3 Cb;
    float Ib;

    vec3 Cf;
    float If;

    float beta;
    float shift;
    float ior;
    float density;

    float lambda;
    float lambfaG;
    float thickness;
    bool scatter;

    bool r;
    bool tt;
    bool trt;
    float Ig;

} material;

uint integrationSteps = 64;

DisneyHairBSDF bsdf;

vec3 integrateOverSphere(float thetaI, float thetaR, float phiD, uint steps) {

    const float PHI_MIN      = 0;   // 0
    const float PHI_MAX      = PI;  // 180

    const float THETA_MIN  = 0.0;
    const float THETA_MAX  = 1.57079632679;   

    float dTheta = (THETA_MAX - THETA_MIN) / steps;
    float dPhi   = (PHI_MAX - PHI_MIN)     / steps;


   
    vec3 f = evalDirectDisneyHairBSDF(thetaI, thetaR, phiD, bsdf, true, true, true);

    atomicAdd(normIntegral.r, f.r);
    atomicAdd(normIntegral.g, f.g);
    atomicAdd(normIntegral.b, f.b);        

}

void main() {

    uint i = gl_GlobalInvocationID.x; // thetaI index
    uint j = gl_GlobalInvocationID.y; // thetaR index
    uint k = gl_GlobalInvocationID.z; // phiD index

    uint steps = integrationSteps;

    if (i >= steps || j >= steps || k >= steps) return;

    // Compute actual angles
    float thetaI = (float(i) + 0.5) * (0.5 * PI) / float(steps);
    float thetaR = (float(j) + 0.5) * (0.5 * PI) / float(steps);
    float phiD   = (float(k) + 0.5) * (PI) / float(steps);

    // Evaluate BSDF
    vec3 f = evalDirectDisneyHairBSDF(thetaI, thetaR, phiD, bsdf, true, true, true);

    // Differential solid angle (for thetaR)
    float dTheta = (0.5 * PI) / float(steps); // from 0 to PI/2
    float dPhi   = PI / float(steps);         // from 0 to PI
    float weight = sin(thetaR) * dTheta * dPhi;

    // Atomic accumulate
    atomicAdd(normIntegral.r, f.r * weight * 4.0);
    atomicAdd(normIntegral.g, f.g * weight * 4.0);
    atomicAdd(normIntegral.b, f.b * weight * 4.0);

}
