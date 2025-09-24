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
    bool useScatter;
};

//Bravais Index
float bravaisIndex(float th, float ior) {
    float sinTheta = sin(th);
    return (sqrt(ior * ior - sinTheta * sinTheta) / cos(th));
}

//Gaussians
float g(float x_mu, float sigma) {
    return exp((-x_mu * x_mu) / (2.0 * sigma * sigma)) / (sqrt(2.0 * PI) * sigma);
}
vec3 g(float x_mu, vec3 sigma) {
    return exp((-x_mu * x_mu) / (2.0 * sigma * sigma)) / (sqrt(2.0 * PI) * sigma);
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

//Local Scattering Lobe Std Dev (Dual-Scattering)
vec3 computeBackStrDev(vec3 a_b, vec3 a_f, vec3 beta_b, vec3 beta_f) {

    vec3 beta_f2 = beta_f * beta_f;
    vec3 beta_b2 = beta_b * beta_b;

    vec3 a_b3 = a_b * a_b * a_b;

    vec3 numerator = a_b * sqrt(2.0 * beta_f2 + beta_b2) + a_b3 * sqrt(2.0 * beta_f2 + 3.0 * beta_b2);
    vec3 denominator = a_b + a_b3 * (2.0 * beta_f + 3.0 * beta_b);
    // denominator = max(denominator, vec3(1e-6));

    vec3 sigma_b = (1.0 + 0.7 * a_f * a_f) * (numerator / denominator);
    return sigma_b;
}

//Local Scattering Lobe Attenuation (Dual-Scattering)
vec3 computeAb(vec3 a_b, vec3 a_f) {

    vec3 afSqr = a_f * a_f;
    vec3 oneMinusAfSqr = max(vec3(1.0) - afSqr, vec3(1e-6)); // Avoid divide-by-zero

    vec3 abCubed = a_b * a_b * a_b;

    vec3 A1 = (a_b * afSqr) / oneMinusAfSqr;
    vec3 A3 = (abCubed * afSqr) / (oneMinusAfSqr * oneMinusAfSqr);

    vec3 Ab = A1 + A3;
    return Ab;
}




vec3 evalDirectHairBSDF(
    float thI,
    float thR,
    float phiD,
    HairBSDF bsdf,
    sampler3D DpTex,
    bool r,
    bool tt,
    bool trt
) {

    //Theta Half
    float thD = (thR - thI) * 0.5; //Theta Difference (0-90º)
    float thH = (thR + thI) * 0.5; //Theta Half

    //Betas & Shifts
    vec3 betas = vec3(bsdf.beta, bsdf.beta * 0.5, bsdf.beta * 2.0);
    vec3 shifts = vec3(bsdf.shift, -bsdf.shift * 0.5, -3.0 * bsdf.shift * 0.5);
    float azBeta = bsdf.azBeta;

    vec3 color = vec3(0.0);
    vec3 direct = vec3(0.0);

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
    vec3 Dp = texture(DpTex, vec3(phiD * ONE_OVER_PI, cos(thD),azBeta)).rgb;

    // float aR = fresnel(bsdf.ior, sqrt(0.5 + 0.5 * dot(wi, wr)));
    float cosThetaD = cos(thI) * cos(thR) + sin(thI) * sin(thR) * cos(phiD);
    float cosThetaH = sqrt(0.5 + 0.5 * cosThetaD); // same as sqrt((1 + dot)/2)
    float aR = fresnel(bsdf.ior, cosThetaH);
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

    color += direct;
    return color;

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
    sampler2D backAttTex,
    sampler2D frontAttTex,
    sampler2D ngTex,
    sampler2D ngtTex,
    sampler2D shiftsTexFront,
    sampler2D shiftsTexBack,
    sampler2D betasTexFront,
    sampler2D betasTexBack,
    float transHairsCount,
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

    // float hairsInFront = directFraction;
    // float hairsInFront = 1.0 - (transHairsCount / 100.0);
    vec3 sigma2F = spread;
    vec3 transF = transDirect;


    //////////////////////////////////////////////////////////////////////////

    //Declare lobes

    vec3 color = vec3(0.0);

    vec3 fDirect = vec3(0.0);
    vec3 fDirectS = vec3(0.0);
    vec3 fDirectB = vec3(0.0);

    vec3 fScatter = vec3(0.0);
    vec3 fScatterS = vec3(0.0);
    vec3 fScatterB = vec3(0.0);

    //Attenuation over fiber

    float idx_thD = clamp(abs(thD * ONE_OVER_PI_HALF),0.01,1.0);

    vec3 a_f = texture(frontAttTex, vec2(idx_thD, 0.5)).rgb;
    vec3 a_b = texture(backAttTex, vec2(idx_thD, 0.5)).rgb;

    vec3 b_f = texture(betasTexFront, vec2(idx_thD, 0.5)).rgb;
    vec3 b_b = texture(betasTexBack, vec2(idx_thD, 0.5)).rgb;

    //////////////////////////////////////////////////////////////////////////
	// Compute S terms (direct + scatter)
	//////////////////////////////////////////////////////////////////////////

    // F Direct S
    /////////////////////////////////////////

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
    vec3 Dp = texture(DpTex, vec3(phi * ONE_OVER_PI, cos(thD),azBeta)).rgb;

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

    fDirectS = (R * bsdf.Rpower + TT * bsdf.TTpower + TRT * bsdf.TRTpower) / (cos(thD) * cos(thD));

    // F Scatter S
    /////////////////////////////////////////
    if(bsdf.useScatter) {

        //Longitudinal
        //-----------------------------------------------

        float mgRr = g(thH - shifts.x, betas.x + sigma2F.r);
        float mgRg = g(thH - shifts.x, betas.x + sigma2F.g);
        float mgRb = g(thH - shifts.x, betas.x + sigma2F.b);
        float mgTTr = g(thH - shifts.y, betas.y + sigma2F.r);
        float mgTTg = g(thH - shifts.y, betas.y + sigma2F.g);
        float mgTTb = g(thH - shifts.y, betas.y + sigma2F.b);
        float mgTRTr = g(thH - shifts.z, betas.z + sigma2F.r);
        float mgTRTg = g(thH - shifts.z, betas.z + sigma2F.g);
        float mgTRTb = g(thH - shifts.z, betas.z + sigma2F.b);

        vec3 mgR = vec3(mgRr,mgRg,mgRb);
        vec3 mgTT =vec3(mgTTr,mgTTg,mgTTb);
        vec3 mgTRT =vec3(mgTRTr,mgTRTg,mgTRTb);

        //Azimuthal
        //-----------------------------------------------

        vec4 ngSample0 = texture(ngTex,vec2(phi * ONE_OVER_PI, abs(thD * ONE_OVER_PI_HALF)));
        vec3 ngSample1 = texture(ngtTex,vec2(phi * ONE_OVER_PI,abs(thD * ONE_OVER_PI_HALF))).rgb;

        vec3 ngR = ngSample0.aaa;
        vec3 ngTT = ngSample0.rgb;
        vec3 ngTRT = ngSample1;

        vec3 Rg = r ? mgR * ngR : vec3(0.0);
        vec3 TTg = tt ? mgTT * ngTT : vec3(0.0);
        vec3 TRTg = trt ? mgTRT * ngTRT : vec3(0.0);

        fScatterS = (Rg * bsdf.Rpower + TTg * bsdf.TTpower + TRTg * bsdf.TRTpower) / (cos(thD) * cos(thD));

    }

    //////////////////////////////////////////////////////////////////////////
	// Compute Back terms (direct + scatter)
	/////////////////////////////////////////////////////////////////////////

    vec3 Ab = computeAb(a_b, a_f);
        // vec3 Ab = computeAb(vec3(0.25), vec3(bsdf.density));
    if(bsdf.useScatter) {


        vec3 sigB = computeBackStrDev(a_b, a_f, b_b, b_f);
        vec3 sigma2B = sigB * sigB;

        float cosThetaD = cos(thD);
        float cos2ThetaD = cosThetaD * cosThetaD;

        float mu = thR + thI;


        // F Direct Back
        /////////////////////////////////////////

        vec3 Gdb = g(mu, sigma2B);
        fDirectB = (2.0 * Ab * Gdb) / ((PI * cos2ThetaD))  * 1000.0;

         // F Scatter Back
        /////////////////////////////////////////

        vec3 Gsb = g(mu, sigma2B + sigma2F);
        fScatterB = (2.0 * Ab * Gsb) / ((PI * cos2ThetaD)) * 1000.0; 


    }

    //////////////////////////////////////////////////////////////////////////
	// Build lobes
	////////////////////////////////////////////////////////////////////////

    fDirect = directFraction * (fDirectS + bsdf.density * fDirectB);
    // fScatter = (transF - vec3(directFraction)) * bsdf.density * (fScatterS + PI *bsdf.density * fScatterB);
    color = (fDirect + fScatter) * cos(thI);

	//////////////////////////////////////////////////////////////////////////
     return color * li;
//    if(Ab.r > 1.0 || Ab.g > 1.0 || Ab.b > 1.0)
//    return vec3(1.0);
if(length(fDirectS) > length(vec3(1.2)) )
return vec3(1.0,0.0,0.0);
    return  vec3(0.0,1.0,0.0);
// if(idx_thD < 0.0 ) return vec3(1.0,0.0,0.0);
//    return vec3(idx_thD);
// return vec3(0.0);



    // if( idx_thI > 0.5) return vec3(1.0,0.0,0.0);
    //  if( idx_thI  < 0.0) return vec3(0.0,0.0,1.0);
    //  if( idx_thI  < 0.5) return vec3(0.0,1.0,0.0);
    // return vec3(0.0,phi * ONE_OVER_PI,0.0);
}