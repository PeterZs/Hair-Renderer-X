#shader compute
#version 460
#include BRDFs/disney_hair_BSDF.glsl

layout(local_size_x = 16, local_size_y = 1, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform writeonly image2D outputFrontAtt;
layout(rgba32f, set = 0, binding = 1) uniform writeonly image2D outputBackAtt;
layout(set = 0, binding = 2) uniform sampler3D DpTex;
layout(rgba32f, set = 0, binding = 5) uniform writeonly image2D outputFrontShifts;
layout(rgba32f, set = 0, binding = 6) uniform writeonly image2D outputBackShifts;
layout(rgba32f, set = 0, binding = 7) uniform writeonly image2D outputFrontBetas;
layout(rgba32f, set = 0, binding = 8) uniform writeonly image2D outputBackBetas;
layout(set = 0, binding = 10) buffer BSDFIntegralBuffer {
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

vec3 integrateOverHemisphere(float thetaI, uint steps, uint hemisphere, out vec3 avgShift, out vec3 avgBeta) {

    const float PHI_MIN      = -1.57079632679; // -π/2
    const float PHI_MAX      =  1.57079632679; //  π/2

    const float THETA_MIN  = 0.0;
    const float THETA_MAX  = 1.57079632679;   

    float dThetaR = (THETA_MAX - THETA_MIN) / steps;
    float dPhiR   = (PHI_MAX - PHI_MIN)     / steps;
    float dPhiI   = (PHI_MAX - PHI_MIN)     / steps;

    vec3 fSum =     vec3(0.0);
    vec3 fAlpha =   vec3(0.0);
    vec3 fBeta =    vec3(0.0);

    vec3 shifts =   vec3(bsdf.shift, -bsdf.shift * 0.5, -3.0 * bsdf.shift * 0.5);
    vec3 betas =    vec3(bsdf.beta, bsdf.beta * 0.5, bsdf.beta * 2.0);
    vec3 powers =   vec3(bsdf.Ir, bsdf.Itt, bsdf.Itrt);

    float cosThetaI = cos(thetaI);

    for (uint x = 0; x < steps; ++x)
    {
        // float phiI = float(x) / float(steps - 1) * (0.5 * PI);
        float phiI = PHI_MIN + (float(x) + 0.5) * dPhiI;

        for (uint y = 0; y < steps; ++y)
        {
            // float thetaR    = float(y)  / float(steps - 1) * (0.5 * PI); // From 0 to 90º
            float thetaR = THETA_MIN + (float(y) + 0.5) * dThetaR;
            // float cosThetaR = cos(thetaR);

            for (uint z = 0; z < steps; ++z)
            {
                float phiR;
                float u = float(z) / float(steps - 1); // 0..1
                if (hemisphere == 0) {
                    // Front: 90° -> 180° -> -90°
                    float phi_raw = 0.5 * PI + u * PI; // π/2 + u * π  => ranges [π/2, 3π/2]
                    // wrap into (-π, π]
                    if (phi_raw > PI) {
                        phiR = phi_raw - 2.0 * PI; // maps (π, 3π/2] -> (-π, -π/2]
                    } else {
                        phiR = phi_raw;            // keeps [π/2, π]
                    }
                } else {
                    // Back: -90° -> 90°
                    phiR = -0.5 * PI + u * PI; // -π/2 + u * π => ranges [-π/2, π/2]
                }

                float phiD = phiR - phiI;

                bsdf.Ir = powers.r;
                bsdf.Itt = powers.g;
                bsdf.Itrt = powers.b;
                vec3 S = evalDirectDisneyHairBSDF(thetaI, thetaR, phiD, bsdf, true, true, true) / normIntegral.rgb;
                
                bsdf.Ir = powers.r * shifts.r;
                bsdf.Itt = powers.g * shifts.g;
                bsdf.Itrt = powers.b * shifts.b;
                vec3 A = evalDirectDisneyHairBSDF(thetaI, thetaR, phiD, bsdf, true, true, true) / normIntegral.rgb;

                bsdf.Ir = powers.r * betas.r;
                bsdf.Itt = powers.g * betas.g;
                bsdf.Itrt = powers.b * betas.b;
                vec3 B = evalDirectDisneyHairBSDF(thetaI, thetaR, phiD, bsdf, true, true, true) / normIntegral.rgb;

                fSum += S * cosThetaI * dThetaR * dPhiR * dPhiI * 2.0;
                fAlpha += A * cosThetaI * dThetaR * dPhiR * dPhiI * 2.0;
                fBeta += B * cosThetaI * dThetaR * dPhiR * dPhiI * 2.0;
            }
        }
    }

    vec3 result = fSum / PI;

    fAlpha /= PI;
    avgShift = fAlpha / result;

    fBeta /= PI;
    avgBeta = fBeta / result;

    return result;
}


void main() {

    // BSDF setup ...........................................................
    
    bsdf.beta = material.beta;
    bsdf.lambda = material.lambda;
    bsdf.lambdaG = material.lambfaG;
    bsdf.shift = material.shift;
    bsdf.ior = material.ior;
    bsdf.density = material.density;

    bsdf.Ir = material.Ir;
    bsdf.Itt = material.Itt;
    bsdf.Itrt = material.Itrt;
    bsdf.Ig = material.Ig;
    bsdf.Ib = material.Ib;
    bsdf.If = material.If;

    bsdf.Cr = material.Cr;
    bsdf.Ctt = material.Ctt;
    bsdf.Ctrt = material.Ctrt;
    bsdf.Cb = material.Cb;
    bsdf.Cf = material.Cf;

    bsdf.angleG = 1.17;


    // Integration Key Params............................................................

    uint  i          = gl_GlobalInvocationID.x;
    uvec2 texSize    = imageSize(outputFrontAtt);
    uint  resolution = texSize.x;
    if (i >= resolution)
        return;
    uint steps = uint(integrationSteps);

    float thetaI = float(i) * (0.5 * PI) / float(resolution - 1);
    float t = float(i) / float(resolution - 1);
    float theta_d = t * (1.57079632679); // 0..π/2

    // Integration Over Front Hemisphere (TT)............................................................

    vec3 avgShiftF = vec3(0.0);
    vec3 avgBetaF = vec3(0.0);
    vec3 fSumF = integrateOverHemisphere(thetaI, steps, 0, avgShiftF, avgBetaF );
    imageStore(outputFrontAtt, ivec2(i, 0), vec4(fSumF, 1.0));
    imageStore(outputFrontShifts, ivec2(i, 0), vec4(avgShiftF, 1.0));
    imageStore(outputFrontBetas, ivec2(i, 0), vec4(avgBetaF, 1.0));

    // Integration Over Back Hemisphere (R & TRT)............................................................

    vec3 avgShiftB = vec3(0.0);
    vec3 avgBetaB = vec3(0.0);
    vec3 fSumB = integrateOverHemisphere(thetaI, steps, 1, avgShiftB, avgBetaB);
    imageStore(outputBackAtt, ivec2(i, 0), vec4(fSumB, 1.0));
    imageStore(outputBackShifts, ivec2(i, 0), vec4(avgShiftB, 1.0));
    imageStore(outputBackBetas, ivec2(i, 0), vec4(avgBetaB, 1.0));
}
