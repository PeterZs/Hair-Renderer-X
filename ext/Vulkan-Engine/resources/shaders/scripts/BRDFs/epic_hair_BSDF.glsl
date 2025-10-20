
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

///////////////////////////////////////////////////////////////////////////////////////////////////
// Utility functions
///////////////////////////////////////////////////////////////////////////////////////////////////

float pow2(float x) {
  return x * x;
}
float saturate(float x) {
  return clamp(x, 0.0, 1.0);
}

float luminance(vec3 color) {
  return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722;
}

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

vec3 evalEpicHairBSDF(vec3 L, vec3 V, vec3 N, float shadow, EpicHairBSDF bsdf, float inBacklit, float area, bool r, bool tt, bool trt, bool scatter ) {

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