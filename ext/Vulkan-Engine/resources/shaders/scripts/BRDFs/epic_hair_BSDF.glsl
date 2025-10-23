
/////////////////////////////////////////////
//EPIC'S UNREAL REAL-TIME ARTIST-FRIENDLY FIT
/////////////////////////////////////////////

#ifndef PI 
#define PI              3.1415926535897932384626433832795
#endif
#define ONE_OVER_PI      (1.0 / PI)
#define ONE_OVER_PI_HALF (2.0 / PI)
#define DEG2RAD(x) ((x) / 180.0 * PI)

// Hair reflectance component (R, TT, TRT, Local Scattering, Global Scattering, Multi Scattering,...)

struct EpicHairBSDF {

  vec3 baseColor;

  float roughness;
  float metallic;
  float specular;

  float shift;
  float ior;

  float Rpower;
  float TTpower;
  float TRTpower;

  bool useLegacyAbsorption;
  bool useSeparableR;
  bool useBacklit;

  bool clampBSDFValue;

  float opaqueVisibility;

  vec3 localScattering;
  vec3 globalScattering;

};

struct HairAverageScattering {
  vec3 A_back;
  vec3 A_front;
};

struct HairTransmittanceMask {
  float visibility;
  float hairCount;
};

///////////////////////////////////////////////////////////////////////////////////////////////////
// Utility functions
///////////////////////////////////////////////////////////////////////////////////////////////////

vec3 hairColorToAbsorption(vec3 C) {
  const float B = 0.3;
  const float b2 = B * B;
  const float b3 = B * b2;
  const float b4 = b2 * b2;
  const float b5 = B * b4;
  const float D = (5.969 - 0.215 * B + 2.532 * b2 - 10.73 * b3 + 5.574 * b4 + 0.245 * b5);

  vec3 L = log(max(C, vec3(1e-6))) / D; // protección contra log(0)

  return L * L; // evita pow(vec3,vec3)
}

float g(float theta, float beta, bool bClampBSDFValue) {
	// Clamp beta for the denominator term, as otherwise the Gaussian normalization returns too high value.
	// This clamps allow to prevent large value for low roughness, while keeping the highlight shape/sharpness 
	// similar.
  const float DenominatorB = bClampBSDFValue ? max(beta, 0.01) : beta;
  return exp(-0.5 * pow2(theta) / (beta * beta)) / (sqrt(2 * PI) * DenominatorB); // No unit-height
}
float g2(float theta, float beta) {
	//const float A = 1.f / sqrt(2 * PI * Variance);
  const float A = 1.;
  return A * exp(-0.5 * pow2(theta) / beta);
}

float fresnel(float cosTheta, float ior) {
  const float n = ior;
  const float F0 = pow2((1 - n) / (1 + n));
  return F0 + (1 - F0) * pow(1 - cosTheta, 5.0);
}

vec3 evalKajiyaKayDiffuseAttenuation(vec3 color, float metallic, vec3 L, vec3 V, vec3 N, float shadow) {
  float kajiyaDiffuse = 1.0 - abs(dot(N, L));

  vec3 fakeNormal = normalize(V - N * dot(V, N));
	//N = normalize( DiffuseN + FakeNormal * 2 );
  N = fakeNormal;

	// Hack approximation for multiple scattering.
  float minValue = 0.0001;
  float wrap = 1.0;
  float NoL = saturate((dot(N, L) + wrap) / pow2(1.0 + wrap));
  float diffuseScatter = (1 / PI) * mix(NoL, kajiyaDiffuse, 0.33) * metallic;
  float luma = luminance(color);
  vec3 baseOverLuma = abs(color / max(luma, minValue));
  vec3 scatterTint = shadow < 1.0 ? pow(baseOverLuma, vec3(1.0 - shadow)) : vec3(1.0);
  return sqrt(abs(color)) * diffuseScatter * scatterTint;
}

vec3 evalMultipleScattering(
  const EpicHairBSDF bsdf,
  const vec3 Fs
) {
  return bsdf.globalScattering * (Fs + bsdf.localScattering) * bsdf.opaqueVisibility;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// Hair BSDF
// Approximation to HairShadingRef using concepts from the following papers:
// [Marschner et al. 2003, "Light Scattering from Human Hair Fibers"]
// [Pekelis et al. 2015, "A Data-Driven Light Scattering Model for Hair"]
///////////////////////////////////////////////////////////////////////////////////////////////////

vec3 evalEpicHairBSDF(vec3 L, vec3 V, vec3 N, float shadow, EpicHairBSDF bsdf, float inBacklit, float area, bool r, bool tt, bool trt, bool scatter) {

  // to prevent NaN with decals
	// OR-18489 HERO: IGGY: RMB on E ability causes blinding hair effect
	// OR-17578 HERO: HAMMER: E causes blinding light on heroes with hair
  float clampedRoughness = clamp(bsdf.roughness, 1.0 / 255.0, 1.0);

	//const vec3 DiffuseN	= OctahedronToUnitVector( GBuffer.CustomData.xy * 2 - 1 );

  const float backlit = bsdf.useBacklit ? inBacklit : 1.0;
  // const float backlit =  1.0;
  // const float backlit = min(inBacklit, bsdf.useBacklit ? GBuffer.CustomData.z : 1.0);

  // THETA
  const float VoL = dot(V, L);
  const float sinThetaL = clamp(dot(N, L), -1.0, 1.0);
  const float sinThetaV = clamp(dot(N, V), -1.0, 1.0);
  float cosThetaD = cos(0.5 * abs(asin(sinThetaV) - asin(sinThetaL)));
	//cosThetaD = abs( cosThetaD ) < 0.01 ? 0.01 : cosThetaD;

  // PHI
  const vec3 Lp = L - sinThetaL * N;
  const vec3 Vp = V - sinThetaV * N;
  const float cosPhi = dot(Lp, Vp) * inversesqrt(dot(Lp, Lp) * dot(Vp, Vp) + 1e-4);
  const float cosHalfPhi = sqrt(saturate(0.5 + 0.5 * cosPhi));
	//const float Phi = acosFast( CosPhi );

  float n = bsdf.ior;
	//float n_prime = sqrt( n*n - 1 + Pow2( CosThetaD ) ) / CosThetaD;
  float n_prime = 1.19 / cosThetaD + 0.36 * cosThetaD;

  float shift = 0.035;
  // float shift = bsdf.shift;
  vec3 alpha = vec3(-shift * 2, shift, shift * 4);
  vec3 beta = vec3(area + pow2(clampedRoughness), area + pow2(clampedRoughness) * 0.5, area + pow2(clampedRoughness) * 2.0);

  vec3 S = vec3(0.0);
  // R

  if(r) {

    const float sa = sin(alpha[0]);
    const float ca = cos(alpha[0]);
    float shiftR = 2 * sa * (ca * cosHalfPhi * sqrt(1 - sinThetaV * sinThetaV) + sa * sinThetaV);
    float betaScale = bsdf.useSeparableR ? sqrt(2.0) * cosHalfPhi : 1.0;
    float Mp = g(sinThetaL + sinThetaV - shiftR, beta[0] * betaScale, bsdf.clampBSDFValue);
    float Np = 0.25 * cosHalfPhi;
    float Fp = fresnel(sqrt(saturate(0.5 + 0.5 * VoL)), n);
    S += vec3(Mp * Np * Fp * (bsdf.specular * 2.0) * mix(1, backlit, saturate(-VoL)));

  }

	// // TT
  if(tt) {

    float Mp = g(sinThetaL + sinThetaV - alpha[1], beta[1], bsdf.clampBSDFValue);

    float a = 1.0 / n_prime;
		//float h = CosHalfPhi * rsqrt( 1 + a*a - 2*a * sqrt( 0.5 - 0.5 * CosPhi ) );
		//float h = CosHalfPhi * ( ( 1 - Pow2( CosHalfPhi ) ) * a + 1 );
    float h = cosHalfPhi * (1.0 + a * (0.6 - 0.8 * cosPhi));
		//float h = 0.4;
		//float yi = asinFast(h);
		//float yt = asinFast(h / n_prime);

    float f = fresnel(cosThetaD * sqrt(saturate(1 - h * h)), n);
    float Fp = pow2(1.0 - f);
    vec3 Tp = vec3(0.0);

    if(bsdf.useLegacyAbsorption) {

      Tp = pow(abs(bsdf.baseColor), vec3(0.5 * sqrt(1.0 - pow2(h * a)) / cosThetaD));

    } else {
			// Compute absorption color which would match user intent after multiple scattering
      const vec3 absorptionColor = hairColorToAbsorption(bsdf.baseColor);
      Tp = exp(-absorptionColor * 2.0 * abs(1.0 - pow2(h * a) / cosThetaD));
    }

		//float t = asin( 1 / n_prime );
		//float d = ( sqrt(2) - t ) / ( 1 - t );
		//float s = -0.5 * PI * (1 - 1 / n_prime) * log( 2*d - 1 - 2 * sqrt( d * (d - 1) ) );
		//float s = 0.35;
		//float Np = exp( (Phi - PI) / s ) / ( s * Pow2( 1 + exp( (Phi - PI) / s ) ) );
		//float Np = 0.71 * exp( -1.65 * Pow2(Phi - PI) );
    float Np = exp(-3.65 * cosPhi - 3.98);

    S += Mp * Np * Fp * Tp * backlit;
  }

	// TRT
  if(trt) {

    float Mp = g(sinThetaL + sinThetaV - alpha[2], beta[2], bsdf.clampBSDFValue);

		//float h = 0.75;
    float f = fresnel(cosThetaD * 0.5, n);
    float Fp = pow2(1.0 - f) * f;
		//vec3 Tp = pow( GBuffer.BaseColor, 1.6 / CosThetaD );
    vec3 Tp = pow(abs(bsdf.baseColor), vec3(0.8 / cosThetaD));

		//float s = 0.15;
		//float Np = 0.75 * exp( Phi / s ) / ( s * Pow2( 1 + exp( Phi / s ) ) );
    float Np = exp(17.0 * cosPhi - 16.78);

    S += Mp * Np * Fp * Tp;
  }

  if(scatter) {
    S = evalMultipleScattering(bsdf, S);
    S += evalKajiyaKayDiffuseAttenuation(bsdf.baseColor, bsdf.metallic, L, V, N, shadow);
  }

  S = -min(-S, 0.0);

  return S;

}


// Dual scattering computation are done here for faster iteration (i.e., does not invalidate tons of shaders)
EpicHairBSDF computeDualScatteringTerms(
  const HairTransmittanceMask TransmittanceMask,
  const HairAverageScattering AverageScattering,
  const vec3 V,
  const vec3 L,
  const vec3 T,
  EpicHairBSDF bsdf
) {
  const float SinThetaL = clamp(dot(T, L), -1.0, 1.0);
  const float SinThetaV = clamp(dot(T, V), -1.0, 1.0);
  const float CosThetaL = sqrt(1.0 - SinThetaL * SinThetaL);
  const float maxAverageScatteringValue = 0.99;

	// Straight implementation of the dual scattering paper 
  const vec3 af = min(vec3(maxAverageScatteringValue), AverageScattering.A_front);
  const vec3 af2 = pow2(af);
  const vec3 ab = min(vec3(maxAverageScatteringValue), AverageScattering.A_back);
  const vec3 ab2 = pow2(ab);
  const vec3 OneMinusAf2 = 1.0 - af2;

  const vec3 A1 = ab * af2 / OneMinusAf2;
  const vec3 A3 = ab * ab2 * af2 / (OneMinusAf2 * pow2(OneMinusAf2));
  const vec3 Ab = A1 + A3;

	// Add a min/max roughness for dual scattering based. This is a bit adhoc, but 
	// * Min/lower bound helps with BSDF being too narrow and causing some fireflies, 
	// * Max/upper bound helps against "too-flat" look due to dual scattering assuming directional lobe (vs. more radially uniform)
  float roughness = clamp(bsdf.roughness, 0.18, 0.6);
  const float Beta_R = pow2(roughness);
  const float Beta_TT = pow2(roughness * 0.5);
  const float Beta_TRT = pow2(roughness * 2);

  const float Shift = 0.035;
  // const float Shift = bsdf.shift;
  const float Shift_R = -0.035 * 2.0;
  const float Shift_TT = 0.035;
  const float Shift_TRT = 0.035 * 4.0;

	// Average density factor (This is the constant used in the original paper)
  const float df = 0.7;
  const float db = 0.7;

	// Always shift the hair count by one to remove self-occlusion/shadow aliasing and have smoother transition
	// This insure the the pow function always starts at 0 for front facing hair
  const float HairCount = max(0.0, float(TransmittanceMask.hairCount) - 1.0);

	// This is a coarse approximation of eq. 13. Normally, Beta_f should be weighted by the 'normalized' 
	// R, TT, and TRT terms 
  const vec3 af_weights = af / (af.r + af.g + af.b);
  const vec3 Beta_f = vec3(dot(vec3(Beta_R, Beta_TT, Beta_TRT), af_weights));
  const vec3 Beta_f2 = Beta_f * Beta_f;
  const vec3 sigma_f2 = Beta_f2 * max(1.0, HairCount);

  const float Theta_d = asin(SinThetaL) + asin(SinThetaV);
  const float Theta_h = Theta_d * 0.5;

	// Global scattering spread 'Sf'
  vec3 Sf = vec3( g2(Theta_h, sigma_f2.r), g2(Theta_h, sigma_f2.g), g2(Theta_h, sigma_f2.b)) / PI;
  const vec3 Tf = pow(AverageScattering.A_front, vec3(HairCount));

	//Overall shift due to the various local scatteing event (all shift & roughnesss should vary with color)
  const vec3 shift_f = vec3(dot(vec3(Shift_R, Shift_TT, Shift_TRT), af_weights));
  const vec3 shift_b = shift_f;
  const vec3 delta_b = shift_b * (1 - 2 * ab2 / pow2(1 - af2)) * shift_f * (2 * pow2(1 - af2) + 4 * af2 * ab2) / ((1 - af2) * (1 - af2) * (1 - af2));

  const vec3 ab_weights = ab / (ab.r + ab.g + ab.b);
  const vec3 Beta_b = vec3(dot(vec3(Beta_R, Beta_TT, Beta_TRT), ab_weights));
  const vec3 Beta_b2 = Beta_b * Beta_b;

  const vec3 sigma_b = (1 + db * af2) * (ab * sqrt(2 * Beta_f2 + Beta_b2) + ab * ab2 * sqrt(2 * Beta_f2 + Beta_b2)) / (ab + ab * ab2 * (2 * Beta_f + 3 * Beta_b));
  const vec3 sigma_b2 = sigma_b * sigma_b;

	// Local scattering Spread 'Sb'
	// In Efficient Implementation of the Dual Scattering Model, the variance for back scattering is the sum of the front & back variances
  vec3 Sb = vec3(g2(Theta_h - delta_b.r, sigma_f2.r + sigma_b2.r), g2(Theta_h - delta_b.g, sigma_f2.g + sigma_b2.g), g2(Theta_h - delta_b.b, sigma_f2.b + sigma_b2.b)) / PI;

	// Different variant for managing sefl-occlusion issue for global scattering
  const vec3 GlobalScattering = mix(vec3(1.0), Tf * Sf * df, saturate(HairCount));
  const vec3 LocalScattering = 2.0 * Ab * Sb * db;

	
  bsdf.globalScattering = GlobalScattering;
  bsdf.localScattering = LocalScattering;
  bsdf.opaqueVisibility = TransmittanceMask.visibility;
  return bsdf;
  
}

HairAverageScattering sampleHairLUT(sampler3D LUTTexture, vec3 InAbsorption, float Roughness, float SinViewAngle) {
  const vec3 RemappedAbsorption = fromLinearAbsorption(InAbsorption);
  const vec2 LUTValue_R = textureLod(LUTTexture, vec3(saturate(abs(SinViewAngle)), saturate(Roughness), saturate(RemappedAbsorption.x)), 0.0).xy;
  const vec2 LUTValue_G = textureLod(LUTTexture, vec3(saturate(abs(SinViewAngle)), saturate(Roughness), saturate(RemappedAbsorption.y)), 0.0).xy;
  const vec2 LUTValue_B = textureLod(LUTTexture, vec3(saturate(abs(SinViewAngle)), saturate(Roughness), saturate(RemappedAbsorption.z)), 0.0).xy;

  HairAverageScattering Output;
  Output.A_front = vec3(LUTValue_R.x, LUTValue_G.x, LUTValue_B.x);
  Output.A_back = vec3(LUTValue_R.y, LUTValue_G.y, LUTValue_B.y);
  return Output;
}

EpicHairBSDF evalHairMultipleScattering(
  const vec3 V,
  const vec3 L,
  const vec3 T,
  HairTransmittanceMask TransmittanceMask,
  sampler3D HairLUTTexture,
  EpicHairBSDF bsdf
) {
	// Hack: Override the actual roughness, with a different value to achieve a specific look
	// const float Roughness = GBuffer.CustomData.x > 0 ? GBuffer.CustomData.x : GBuffer.Roughness;
	// const float Backlit = GBuffer.CustomData.z;

	// Compute the transmittance based on precompute Hair transmittance LUT
  const float SinLightAngle = dot(L, T);
  const HairAverageScattering AverageScattering = sampleHairLUT(HairLUTTexture, bsdf.baseColor, bsdf.roughness, SinLightAngle);
  // const HairAverageScattering AverageScattering;

  return computeDualScatteringTerms(TransmittanceMask, AverageScattering, V, L, T, bsdf);

}