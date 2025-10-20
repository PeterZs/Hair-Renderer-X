#shader compute
#version 460
#include BRDFs/disney_hair_BSDF.glsl
#extension GL_EXT_shader_atomic_float: enable

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

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

const uint STEPS = 64;
const uint STEPS_C = 64*64*64;

DisneyHairBSDF bsdf;

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

   vec3 fSum = vec3(0.0); 

    // Differential solid angle (for thetaR)
    float dTheta = (0.5 * PI) / float(STEPS); // from 0 to PI/2
    float dPhi   = PI / float(STEPS);         // from 0 to PI


    for(int i = 0; i < STEPS; i++) {
        float thetaI = (float(i) + 0.5) * (0.5 * PI) / float(STEPS);

        for(int j = 0; j < STEPS; j++) {
            float thetaR = (float(j) + 0.5) * (0.5 * PI) / float(STEPS);

            for(int k = 0; k < STEPS; k++) {
            float phiD   = (float(k) + 0.5) * (PI) / float(STEPS);
        
            float weight = cos(thetaR) * sin(thetaR) * dTheta * dPhi;
            
            // Evaluate BSDF
            // vec3 fSum += evalDirectDisneyHairBSDF(thetaI, thetaR, phiD, bsdf, true, true, true);
            fSum += vec3(1.0) * weight * 4.0;
                
            }
        }
    }

    normIntegral.rgb = fSum; 

   

}
