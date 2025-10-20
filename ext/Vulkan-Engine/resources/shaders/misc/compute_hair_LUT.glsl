#shader compute
#version 460
#include utils.glsl
#include BRDFs/epic_hair_BSDF.glsl
#include montecarlo.glsl

#define TILE_PIXEL_SIZE 8
layout(local_size_x = TILE_PIXEL_SIZE, local_size_y = TILE_PIXEL_SIZE, local_size_z = TILE_PIXEL_SIZE) in;

layout(rgba32f, set = 0, binding = 0) uniform image3D hairLUT;

#define JITTER_VIEW 0
#define LUT_TYPE_DUALSCATTERING

void main() {

    uint AbsorptionCount;
    uint RoughnessCount;
    uint ThetaCount;
    uint SampleCountScale;

#ifdef LUT_TYPE_DUALSCATTERING

	// 3D LUT is organized as follow 
	//
	//      Z
	//	   ^
	//    /
	//   Absorption
	//  /
	// /
	//  ----- Theta ----> X
	// |
	// |
	// Roughness 
	// |
	// |
	// V
	// Y
    const uint3 PixelCoord = gl_GlobalInvocationID.xyz;

    const float SinAngle = saturate(float(PixelCoord.x + 0.5) / ThetaCount);
    const float Roughness = saturate(float(PixelCoord.y + 0.5) / RoughnessCount);
    const float Absorption = saturate(float(PixelCoord.z + 0.5) / AbsorptionCount);
    const float CosAngle = sqrt(1 - SinAngle * SinAngle);

    EpicHairBSDF bsdf;
    bsdf.specular = 0.5;
    bsdf.baseColor = toLinearAbsorption(Absorption.xxx);	// Perceptual absorption
    bsdf.metallic = 0.0;		 							// This disable the fake multiple scattering
    bsdf.roughness = Roughness; 							// Perceptual roughness
    bsdf.useSeparableR = true;
    bsdf.clampBSDFValue = false;
    bsdf.useLegacyAbsorption = false;

    vec4 CustomData = vec4(0.0, 0.0, 1.0, 0.0); // Backlit

    float FrontHemisphereOutput = 0.0;
    float BackHemisphereOutput = 0.0;

    uint FrontHemisphereCount = 0.0;
    uint BackHemisphereCount = 0.0;

    const uint LocalThetaSampleCount = max(1, SampleCountScale * mix(128, 64, Roughness));
    const uint LocalPhiSampleCount = max(1, SampleCountScale * mix(128, 32, Roughness));
    const uint LocalViewSampleCount = max(1, SampleCountScale * 16);

    const float Area = 0.0;			// This is used for faking area light sources by increasing the roughness of the surface. Disabled = 0.
    const float Backlit = 1.0; 		// This is used for suppressing the R & TT terms when when the lighting direction comes from behind. Disabled = 1.
    const vec3 N = vec3(0.0, 0.0, 1.0); // N is the vector parallel to hair pointing toward root. I.e., the tangent T is up
    const vec3 V = vec3(CosAngle, 0.0, SinAngle);
    const float OpaqueVisibility = 1.0;
    // HairTransmittanceData TransmittanceData = InitHairStrandsTransmittanceData();

    const float MaxCosThetaRadius = cos(0.25 * PI / float(ThetaCount)); // [0, Pi/2] / ThetaCount which is divided by 2 for getting the actual radius
    mat3 ToViewBasis = getTangentBasis(V);

	#if JITTER_VIEW == 1
    for(uint ViewIt = 0; ViewIt < LocalViewSampleCount; ++ViewIt)
	#endif
        for(uint SampleItY = 0; SampleItY < LocalPhiSampleCount; ++SampleItY) 
        for(uint SampleItX = 0; SampleItX < LocalThetaSampleCount; ++SampleItX) {	
		// Sample a small solid around the view direction in order to average the small differences
		// This allows to fight undersampling for low roughnesses
		#if JITTER_VIEW == 1
                const vec2 ViewU = Hammersley(ViewIt, LocalViewSampleCount, 0);
                const vec4 ViewSample = UniformSampleCone(ViewU, MaxCosThetaRadius);
                const vec3 JitteredV = mul(ViewSample, ToViewBasis);
                const float ViewPdf = 1;
		#else
                const vec3 JitteredV = V;
                const float ViewPdf = 1;
		#endif

		// Naive uniform sampling
		// @todo: important sampling of the Hair BSDF. The integration is too noisy for low roughness with uniform sampling
                const vec2 jitter = R2Sequence(SampleItX + SampleItY * LocalThetaSampleCount); // vec2(0.5f, 0.5f);
                const vec2 u = (vec2(SampleItX, SampleItY) + jitter) / vec2(LocalThetaSampleCount, LocalPhiSampleCount);
                const vec4 SampleDirection = UniformSampleSphere(u.yx);
                const float SamplePdf = SampleDirection.w;
                const vec3 L = SampleDirection.xyz;
                const vec3 BSDFValue = HairShading(GBufferData, L, JitteredV, N, OpaqueVisibility, TransmittanceData, Backlit, Area, 0);

		// As in the original paper "Dual scattering approximation for fast multiple-scattering in hair", the average front/back scatter are cos-weighted (eq. 12). 
                const float CosL = 1.;// abs(SampleDirection.x);

		// The view direction is aligned with the positive X Axis. This means:
		// * the back hemisphere (R / TRT) is on the positive side of X
		// * the front hemisphere (TT) is on the negative side of X
                const bool bIsBackHemisphere = SampleDirection.x > 0;
                if(bIsBackHemisphere) {
                    BackHemisphereOutput += CosL * BSDFValue.x / SamplePdf;
                    ++BackHemisphereCount;
                } else {
                    FrontHemisphereOutput += CosL * BSDFValue.x / SamplePdf;
                    ++FrontHemisphereCount;
                }
            }

    const float HemisphereFactor = 0.5;
    OutputColor[PixelCoord] = vec4(saturate(FrontHemisphereOutput / FrontHemisphereCount * HemisphereFactor), saturate(BackHemisphereOutput / BackHemisphereCount * HemisphereFactor), 0, 1);
#endif
}
