#shader compute
#version 460
#include BRDFs/hair_BSDF.glsl

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 2) uniform sampler3D DpTex;
layout(rgba32f, set = 0, binding = 3) uniform writeonly image2D outputNG;
layout(rgba32f, set = 0, binding = 4) uniform writeonly image2D outputNGTRT;

layout(set = 1, binding = 1) uniform MaterialUniforms {
    vec3  sigma_a;
    float thickness;

    float beta;
    float shift;
    float ior;
    float density;

    float Rpower;
    float TTpower;
    float TRTpower;
    float scatter;

    float azBeta;
    bool  r;
    bool  tt;
    bool  trt;

    int integrationSteps;
}
material;

uint integrationSteps = 64;

HairBSDF bsdf;



void main() {
    // BSDF setup ............................................................

    bsdf.beta    = material.beta;
    bsdf.azBeta  = material.azBeta;
    bsdf.shift   = material.shift;
    bsdf.sigma_a = material.sigma_a;
    bsdf.ior     = material.ior;
    bsdf.density = material.density;

    bsdf.Rpower   = material.Rpower;
    bsdf.TTpower  = material.TTpower;
    bsdf.TRTpower = material.TRTpower;

    // Integration Key Params............................................................

    uint  i          = gl_GlobalInvocationID.x;
    uint  j          = gl_GlobalInvocationID.y;
    uvec2 texSize    = imageSize(outputNG);
    uint  resolution = texSize.x;

    if (i >= resolution || j >= resolution)
        return;

    uint steps = uint(integrationSteps);

    float phi = float(i) / float(resolution - 1) * PI;
    float thD = float(j)  / float(resolution - 1) * (0.5 * PI);

    // Integration ............................................................

    const float dPhiD   = (0.5 * PI) / float(steps - 1);

    float ngR = 0.0;
    vec3 ngTT = vec3(0.0);
    vec3 ngTRT = vec3(0.0);
    const float  TWO_OVER_PI = 2.0 / PI;

    for (uint x = 0; x < steps; ++x)
    {
        // float phi_p = 0.5 * PI + float(x) * (0.5 * PI) / float(steps - 1); // From 90º to 180º
        float phi_p = (0.5*PI) + (float(x) / float(steps-1)) * (0.5*PI);
        // float phi_D =  phi_p - phi;
        float phi_D =  abs(phi - phi_p);

        vec3 Dp = texture(DpTex, vec3(phi_D * ONE_OVER_PI, cos(thD),bsdf.azBeta)).rgb;

        // float aR = fresnel(bsdf.ior, sqrt(0.5 + 0.5 * dot(wi, wr)));
        // vec3 nR = vec3(aR * Dp.x);

        const float hTT = 0.0;
        vec3 aTT = Ap(1, hTT, bsdf.ior, thD, bsdf.sigma_a);
        // ngTT += aTT * Dp.y * dPhiD * TWO_OVER_PI;
        ngTT += aTT * Dp.y;

        const float hTRT = sqrt(3.0) * 0.5;
        vec3 aTRT = Ap(2, hTRT, bsdf.ior, thD, bsdf.sigma_a);
        // ngTRT += aTRT * Dp.z * dPhiD * TWO_OVER_PI;
        ngTRT += aTRT * Dp.z;

    }

    ngTT *= (PI * 0.5) / float(steps);
    ngTT = ngTT * (2.0 / PI);
    ngTRT *= (PI * 0.5) / float(steps);
    ngTRT = ngTRT * (2.0 / PI);

    imageStore(outputNG, ivec2(i, j), vec4(ngTT, 1.0));
    imageStore(outputNGTRT, ivec2(i, j), vec4(ngTRT, 1.0));

}
