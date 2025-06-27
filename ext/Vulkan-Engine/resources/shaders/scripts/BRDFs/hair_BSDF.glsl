/////////////////////////////////////////////
// .....
/////////////////////////////////////////////

#ifndef PI 
#define PI              3.1415926535897932384626433832795
#endif
#define ONE_OVER_PI      (1.0 / PI)
#define ONE_OVER_PI_HALF (2.0 / PI)
#define DEG2RAD(x) ((x) / 180.0 * PI)

struct HairBSDF {
    vec3 tangent;

    float beta;
    float azBeta;
    float shift;
    vec3 sigma_a;
    float density;
    float ior;

    //Aux
    float Rpower;
    float TTpower;
    float TRTpower;
    bool localScatter;
    bool globalScatter;
};

//Bravais Index
float bravaisIndex(float th, float ior) {
    float sinTheta = sin(th);
    return (sqrt(ior * ior - sinTheta * sinTheta) / cos(th));
}

//Gaussian for M term
float g(float thH, float beta) {
    return exp((-thH * thH) / (2.0 * beta * beta)) / (sqrt(2.0 * PI) * beta);
}

//Schlick's approx
float fresnel(float ior, float cosTheta) {
    float F0 = ((1.0 - ior) * (1.0 - ior)) / ((1.0 + ior) * (1.0 + ior));
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

//Transmittance
vec3 T(vec3 sigma_a, float gammaT) {
    return exp(-2.0 * sigma_a * (1.0 + cos(2.0 * gammaT)));
}

//Attenuation
vec3 Ap(int p, float h, float ior, float thD, vec3 sigma_a) {
    //Aproximation by Epic/Frostbyte/Unity
    float f = fresnel(ior, cos(thD) * sqrt(1.0 - (h * h)));

    //Actual Bravais Index
    float iorPerp = bravaisIndex(thD, ior);
    float gammaT = asin(h / iorPerp);

    //Transmittance
    vec3 t = T(sigma_a, gammaT);

    return ((1 - f) * (1 - f)) * pow(f, p - 1) * pow(t, vec3(p));
}

vec3 evalHairBSDF(
    vec3 wi,               //Light vector
    vec3 wr,               //View vector
    vec3 li,
    HairBSDF bsdf,
    vec3 transDirect,
    vec3 spread,
    float directFraction,
    sampler3D DpTex,
    sampler2D attTex,
    sampler2D NgTex,
    bool r,
    bool tt,
    bool trt
) {

	//////////////////////////////////////////////////////////////////////////
	// Frame Set Up
	//////////////////////////////////////////////////////////////////////////

    //Theta
    vec3 u = bsdf.tangent;
    float sin_thI = dot(wi, u);
    float thI = asin(sin_thI);
    float sin_thR = dot(wr, u);
    float thR = asin(sin_thR);

    float thD = (thR - thI) * 0.5; //Theta Difference (0-90º)
    float thH = (thR + thI) * 0.5; //Theta Half

    //Phi   
    vec3 azI = normalize(wi - sin_thI * u);
    vec3 azR = normalize(wr - sin_thR * u);
    float cosPhi = dot(azI, azR) * inversesqrt(dot(azI, azI) * dot(azR, azR) + 1e-4); 
    float phi = acos(cosPhi); //(0-180º)

    //Betas & Shifts
    vec3 betas = vec3(bsdf.beta, bsdf.beta * 0.5, bsdf.beta * 2.0);
    vec3 shifts = vec3(bsdf.shift, -bsdf.shift * 0.5, -3.0 * bsdf.shift * 0.5);
    float azBeta = bsdf.azBeta;

    //////////////////////////////////////////////////////////////////////////

    vec3 color = vec3(0.0);
    vec3 direct = vec3(0.0);
    vec3 SBack = vec3(0.0);
    vec3 SFront = vec3(0.0);

    //////////////////////////////////////////////////////////////////////////
	// Local Scattering
	//////////////////////////////////////////////////////////////////////////

    // ..........

    //////////////////////////////////////////////////////////////////////////
	// Direct Illumination
	//////////////////////////////////////////////////////////////////////////

    //Longitudinal
    //-----------------------------------------------

    float mR = g(thH - shifts.x, betas.x);
    float mTT = g(thH - shifts.y, betas.y);
    float mTRT = g(thH - shifts.z, betas.z);

    //Azimuthal
    //-----------------------------------------------

    //Far-Field Distribution
    //(phi between 0 and pi)
    //(cos between 0 and 1)
    vec3 Dp = texture(DpTex, vec3(phi * ONE_OVER_PI , cos(thD), azBeta )).rgb;
    // vec3 Dp = texture(DpTex, vec2(phi * ONE_OVER_PI , cos(thD) )).rgb; 

    /*
   EPIC GAMES FITTING OF Far-Field Distribution
    */
    // vec3 Dp;
    // Dp.x = 0.25 * sqrt(clamp(0.5 + 0.5 * cosPhi, 0.0, 1.0));
    // Dp.y = exp(-3.65 * cosPhi - 3.98);
    // Dp.z = exp(17 * cosPhi - 16.78);

    float aR = fresnel(bsdf.ior, sqrt(0.5 + 0.5 * dot(wi, wr)));
    vec3 nR = vec3(aR * Dp.x);

    const float hTT = 0.0;
    vec3 aTT = Ap(1, hTT, bsdf.ior, thD, bsdf.sigma_a);
    vec3 nTT = aTT * Dp.y;

    const float hTRT = sqrt(3.0) * 0.5;
    vec3 aTRT = Ap(2, hTRT, bsdf.ior, thD, bsdf.sigma_a);
    vec3 nTRT = aTRT * Dp.z;

    // Sum lobes
    //-----------------------------------------------

    vec3 R = r ? mR * nR : vec3(0.0);
    vec3 TT = tt ? mTT * nTT : vec3(0.0);
    vec3 TRT = trt ? mTRT * nTRT : vec3(0.0);

    direct = (R * bsdf.Rpower + TT * bsdf.TTpower + TRT * bsdf.TRTpower) / (cos(thD) * cos(thD));

    //////////////////////////////////////////////////////////////////////////
	// Global Scattering
	//////////////////////////////////////////////////////////////////////////

    // ..........

	//////////////////////////////////////////////////////////////////////////

    color += direct;
     return color * li;


    // if( phi * ONE_OVER_PI > 0.5) return vec3(1.0,0.0,0.0);
    //  if( phi * ONE_OVER_PI  < 0.0) return vec3(0.0,0.0,1.0);
    //  if( phi * ONE_OVER_PI  < 0.5) return vec3(0.0,1.0,0.0);
    // return vec3(0.0,phi * ONE_OVER_PI,0.0);
}