#shader compute
#version 460
#include BRDFs/hair_BSDF.glsl

layout(local_size_x = 16, local_size_y = 1, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform writeonly image2D outputFrontAtt;
layout(rgba32f, set = 0, binding = 1) uniform writeonly image2D outputBackAtt;
layout(set = 0, binding = 2) uniform sampler3D DpTex;
layout(rgba32f, set = 0, binding = 5) uniform writeonly image2D outputFrontShifts;
layout(rgba32f, set = 0, binding = 6) uniform writeonly image2D outputBackShifts;
layout(rgba32f, set = 0, binding = 7) uniform writeonly image2D outputFrontBetas;
layout(rgba32f, set = 0, binding = 8) uniform writeonly image2D outputBackBetas;

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





vec3 integrateOverHemisphere2(float theta_d, uint steps, uint hemisphere, out vec3 avgShift, out vec3 avgBeta) {

    // ----------------------------------------------
    // Configuración
    // ----------------------------------------------
    const int N_THETA_R      = 64;   
    const int N_PHI_R        = 64;   
    const int N_PHI_I        = 64;   

    const float THETA_R_MIN  = hemisphere == 0 ? 0.0 : - 1.57079632679 ;
    const float THETA_R_MAX  = hemisphere == 0 ? 1.57079632679 : 0.0;  // 

    const float PHI_MIN      = -1.57079632679; // -π/2
    const float PHI_MAX      =  1.57079632679; //  π/2

    // Diferenciales
    float dThetaR = (THETA_R_MAX - THETA_R_MIN) / float(N_THETA_R);
    float dPhiR   = (PHI_MAX - PHI_MIN)       / float(N_PHI_R);
    float dPhiI   = (PHI_MAX - PHI_MIN)       / float(N_PHI_I);

    vec3 shifts = vec3(bsdf.shift, -bsdf.shift * 0.5, -3.0 * bsdf.shift * 0.5);
    vec3 betas = vec3(bsdf.beta, bsdf.beta * 0.5, bsdf.beta * 2.0);
    vec3 powers = vec3(bsdf.Rpower, bsdf.TTpower, bsdf.TRTpower);


    // Acumulador
    vec3 fSum = vec3(0.0);
    vec3 fAlpha = vec3(0.0);
    vec3 fBeta = vec3(0.0);

    for (int iThetaR = 0; iThetaR < N_THETA_R; iThetaR++) {
        float theta_r = THETA_R_MIN + (float(iThetaR) + 0.5) * dThetaR;

        // θi = 2θd - θr
        float theta_i = 2.0 * theta_d - theta_r;

        // Puedes descartar si theta_i se sale de [0, π/2], etc
        // pero aquí no corto nada para no romper integrales:
        // if(theta_i < 0.0 || theta_i > 1.5707963) continue;

        for (int iPhiR = 0; iPhiR < N_PHI_R; iPhiR++) {
            float phi_r = PHI_MIN + (float(iPhiR) + 0.5) * dPhiR;

            for (int iPhiI = 0; iPhiI < N_PHI_I; iPhiI++) {
                float phi_i = PHI_MIN + (float(iPhiI) + 0.5) * dPhiI;

                // Evaluación de la BSDF
                float phiD = abs(phi_r - phi_i);

                bsdf.Rpower = powers.r;
                bsdf.TTpower = powers.g;
                bsdf.TRTpower = powers.b;
                vec3 fval = evalDirectHairBSDF(theta_i, theta_r, phiD, bsdf, DpTex, true, true, true);
                // vec3 fval = vec3(1.0);

                
                bsdf.Rpower = shifts.r;
                bsdf.TTpower = shifts.g;
                bsdf.TRTpower = shifts.b;
                vec3 alphaVal = evalDirectHairBSDF(theta_i, theta_r, phiD, bsdf, DpTex, true, true, true);

                bsdf.Rpower = betas.r;
                bsdf.TTpower = betas.g;
                bsdf.TRTpower = betas.b;
                vec3 betaVal = evalDirectHairBSDF(theta_i, theta_r, phiD, bsdf, DpTex, true, true, true);

                // Factor cosθr
                fSum += fval * cos(theta_r);;
                fAlpha += alphaVal * cos(theta_r);
                fBeta += betaVal * cos(theta_r);
            }
        }
    }

    // Multiply by 1/Pi
    vec3 integral =
        fSum *
        (dThetaR * dPhiR * dPhiI) *
        (1.0 / 3.14159265359);

    //Compute average beta and shift values
    fAlpha = fAlpha * (dThetaR * dPhiR * dPhiI) *
        (1.0 / 3.14159265359);
    avgShift = fAlpha / integral;

    fBeta = fBeta * (dThetaR * dPhiR * dPhiI) *
        (1.0 / 3.14159265359);
    avgBeta = fBeta / integral;

    return integral;

}
vec3 integrateOverHemisphere(float thetaI, uint steps, uint hemisphere, out vec3 avgShift, out vec3 avgBeta) {

    const float PHI_MIN      = -1.57079632679; // -π/2
    const float PHI_MAX      =  1.57079632679; //  π/2

    const float THETA_MIN  = 0.0;
    const float THETA_MAX  = 1.57079632679;   

    float dThetaR = (THETA_MAX - THETA_MIN) / steps;
    float dPhiR   = (PHI_MAX - PHI_MIN)       / steps;
    float dPhiI   = (PHI_MAX - PHI_MIN)       / steps;

    vec3 fSum = vec3(0.0);
    vec3 fAlpha = vec3(0.0);
    vec3 fBeta = vec3(0.0);

    vec3 shifts = vec3(bsdf.shift, -bsdf.shift * 0.5, -3.0 * bsdf.shift * 0.5);
    vec3 betas = vec3(bsdf.beta, bsdf.beta * 0.5, bsdf.beta * 2.0);
    vec3 powers = vec3(bsdf.Rpower, bsdf.TTpower, bsdf.TRTpower);

    for (uint x = 0; x < steps; ++x)
    {
        // float phiI = float(x) / float(steps - 1) * (0.5 * PI);
        float phiI = PHI_MIN + (float(x) + 0.5) * dPhiI;

        for (uint y = 0; y < steps; ++y)
        {
            // float thetaR    = float(y)  / float(steps - 1) * (0.5 * PI); // From 0 to 90º
            float thetaR = THETA_MIN + (float(y) + 0.5) * dThetaR;
            float cosThetaR = cos(thetaR);

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

                bsdf.Rpower = powers.r;
                bsdf.TTpower = powers.g;
                bsdf.TRTpower = powers.b;
                vec3 S = evalDirectHairBSDF(thetaI, thetaR, phiD, bsdf, DpTex, true, true, true);
                // S = vec3(1.0);

                
                bsdf.Rpower = shifts.r;
                bsdf.TTpower = shifts.g;
                bsdf.TRTpower = shifts.b;
                vec3 A = evalDirectHairBSDF(thetaI, thetaR, phiD, bsdf, DpTex, true, true, true);

                bsdf.Rpower = betas.r;
                bsdf.TTpower = betas.g;
                bsdf.TRTpower = betas.b;
                vec3 B = evalDirectHairBSDF(thetaI, thetaR, phiD, bsdf, DpTex, true, true, true);

                fSum += S * cosThetaR * dThetaR * dPhiR * dPhiI;
                fAlpha += A * cosThetaR * dThetaR * dPhiR * dPhiI;
                fBeta += B * cosThetaR * dThetaR * dPhiR * dPhiI;
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
