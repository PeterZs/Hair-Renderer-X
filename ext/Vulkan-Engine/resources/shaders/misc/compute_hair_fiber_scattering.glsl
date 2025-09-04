#shader compute
#version 460
#include BRDFs/hair_BSDF.glsl

layout(local_size_x = 16, local_size_y = 1, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform writeonly image2D outputFrontAtt;
layout(rgba32f, set = 0, binding = 1) uniform writeonly image2D outputBackAtt;
layout(set = 0, binding = 2) uniform sampler2D DpTex;

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

vec3 integrateOverHemisphere(float thetaI, uint steps, uint hemisphere) {

    const float dThetaR = (0.5 * PI) / float(steps - 1);
    const float dPhiD   = (0.5 * PI) / float(steps - 1);

    vec3 fSum = vec3(0.0);

    for (uint x = 0; x < steps; ++x)
    {
        float thetaR    = float(x) * (0.5 * PI) / float(steps - 1); // From 0 to 90º
        float cosThetaR = cos(thetaR);

        for (uint y = 0; y < steps; ++y)
        {
            float phiD;
            if (hemisphere == 0)
            {
                phiD = 0.5 * PI + float(y) * (0.5 * PI) / float(steps - 1); // From 90º to 180º
            } else
            {
                phiD = float(y) * (0.5 * PI) / float(steps - 1); // From 0º to 90º
            }

            vec3 S = evalDirectHairBSDF(thetaI, thetaR, phiD, bsdf, DpTex, false, true, true);
            fSum += S * cosThetaR * dThetaR * dPhiD * 4.0;
        }
    }

    return fSum;
}

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
    uvec2 texSize    = imageSize(outputFrontAtt);
    uint  resolution = texSize.x;
    if (i >= resolution)
        return;
    uint steps = uint(integrationSteps);

    float thetaI = float(i) * (0.5 * PI) / float(resolution - 1);

    // Integration Over Front Hemisphere (TT)............................................................

    vec3 fSumF = integrateOverHemisphere(thetaI, steps, 0);
    imageStore(outputFrontAtt, ivec2(i, 0), vec4(fSumF, 1.0));

    // Integration Over Back Hemisphere (R & TRT)............................................................

    vec3 fSumB = integrateOverHemisphere(thetaI, steps, 1);
    imageStore(outputBackAtt, ivec2(i, 0), vec4(fSumB, 1.0));
}
