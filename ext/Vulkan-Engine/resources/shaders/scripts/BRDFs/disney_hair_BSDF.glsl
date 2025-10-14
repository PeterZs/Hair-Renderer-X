/////////////////////////////////////////////
// .....
/////////////////////////////////////////////

#ifndef PI
#define PI              3.1415926535897932384626433832795
#endif
#define ONE_OVER_PI      (1.0 / PI)
#define ONE_OVER_PI_HALF (2.0 / PI)
#define DEG2RAD(x) ((x) / 180.0 * PI)

struct DisneyHairBSDF {
    vec3 tangent;

    float beta;
    float lambda;
    float shift;
    float density;
    float ior;

    //Glints
    float lambdaG;
    float angleG; // between 30º -> 45º

    //Colors
    vec3 Cr;
    vec3 Ctt;
    vec3 Ctrt;
    vec3 Cb;
    vec3 Cf;

    //Intensity
    float Ir;
    float Itt;
    float Itrt;
    float Ig;
    float Ib;
    float If;

    bool useScatter;

};

float g(float x, float sigma) { //Unit-Height Gaussian
    return exp(-(x * x) / (2.0 * sigma * sigma));
}

float Nr(float phi) { //phi = 0º -> 180º
    return cos(phi * 0.5);
}
float Ntt(float phi, float lambda) {
    return g(PI - phi, lambda);
}
float NtrtMinusGlint(float phi) {
    return cos(phi * 0.5);
}
float Nglint(float phi, float lambdaG, float IG, float angleG) {
    return IG * g(angleG - phi, lambdaG);
}
float Ntrt(float phi, float lambdaG, float IG, float angleG) {
    return NtrtMinusGlint(phi) + Nglint(phi, lambdaG, IG, angleG);
}

vec3 evalDirectDisneyHairBSDF(
    float thI,
    float thR,
    float phiD,
    DisneyHairBSDF bsdf,
    bool r,
    bool tt,
    bool trt
) {

    //Theta Half
    float thD = abs(thR - thI) * 0.5; //Theta Difference (0-90º)
    float thH = (thR + thI); //Theta Half

    //Betas & Shifts
    vec3 betas = vec3(bsdf.beta, bsdf.beta * 0.5, bsdf.beta * 2.0);
    vec3 shifts = vec3(bsdf.shift, -bsdf.shift * 0.5, -3.0 * bsdf.shift * 0.5);

    //////////////////////////////////////////////////////////////////////////
	// Direct Illumination
	//////////////////////////////////////////////////////////////////////////

    //Longitudinal
    //-----------------------------------------------

    float Mr = g(thH - shifts.x, betas.x);
    float Mtt = g(thH - shifts.y, betas.y);
    float Mtrt = g(thH - shifts.z, betas.z);

    //Azimuthal
    //-----------------------------------------------

    float Nr = Nr(phiD);
    float Ntt = Ntt(phiD, bsdf.lambda);
    float Ntrt = Ntrt(phiD, bsdf.lambdaG, bsdf.Ig, bsdf.angleG);

    // Sum lobes
    //-----------------------------------------------

    vec3 R = r ? Mr * Nr * bsdf.Cr * bsdf.Ir : vec3(0.0);
    vec3 TT = tt ? Mtt * Ntt * bsdf.Ctt * bsdf.Itt  : vec3(0.0);
    vec3 TRT = trt ? Mtrt * Ntrt * bsdf.Ctrt * bsdf.Itrt  : vec3(0.0);

    //-----------------------------------------------

    vec3 direct = (R + TT + TRT) / (cos(thD) * cos(thD));
    return direct;

}

vec3 evalDisneyHairBSDF(
    vec3 wi,               //Light vector
    vec3 wr,               //View vector
    vec3 li,
    DisneyHairBSDF bsdf,
    vec3 transDirect,
    vec3 spread,
    float directFraction,
    sampler2D MGItex,
    sampler2D NGItex,
    sampler2D NGITRTtex,
    sampler3D GItex,
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

    // float thD = (thR - thI) * 0.5; //Theta Difference (0-90º)
    float thD = abs(thR - thI) * 0.5; //Theta Difference (0-90º)
    float thH = (thR + thI) * 0.5; //Theta Half

    //Phi
    vec3 azI = normalize(wi - sin_thI * u);
    vec3 azR = normalize(wr - sin_thR * u);
    float cosPhi = dot(azI, azR) * inversesqrt(dot(azI, azI) * dot(azR, azR) + 1e-4);
    float phi = acos(cosPhi); //(0-180º)

    //Betas & Shifts
    vec3 betas = vec3(bsdf.beta, bsdf.beta * 0.5, bsdf.beta * 2.0);
    vec3 shifts = vec3(bsdf.shift, -bsdf.shift * 0.5, -3.0 * bsdf.shift * 0.5);

    //////////////////////////////////////////////////////////////////////////

    // float hairsInFront = directFraction;
    // float hairsInFront = 1.0 - (transHairsCount / 100.0);
    vec3 sigma2F = sqrt(spread);
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


    //////////////////////////////////////////////////////////////////////////
	// Compute S terms (direct + scatter)
	//////////////////////////////////////////////////////////////////////////

    // F Direct S
    //////////////////////////////////////////////////////////////////////////

    //Longitudinal
    //-----------------------------------------------

    float Mr = g(thH - shifts.x, betas.x);
    float Mtt = g(thH - shifts.y, betas.y);
    float Mtrt = g(thH - shifts.z, betas.z);

    //Azimuthal
    //-----------------------------------------------

    float Nr = Nr(phi);
    float Ntt = Ntt(phi, bsdf.lambda);
    float Ntrt = Ntrt(phi, bsdf.lambdaG, bsdf.Ig, bsdf.angleG);

    // Sum lobes
    //-----------------------------------------------

    vec3 R = r ? Mr * Nr * bsdf.Cr * bsdf.Ir : vec3(0.0);
    vec3 TT = tt ? Mtt * Ntt * bsdf.Ctt * bsdf.Itt  : vec3(0.0);
    vec3 TRT = trt ? Mtrt * Ntrt * bsdf.Ctrt * bsdf.Itrt  : vec3(0.0);

    //-----------------------------------------------

     fDirectS = (R + TT + TRT) / (cos(thD) * cos(thD));

   

    //////////////////////////////////////////////////////////////////////////
	// Compute Back terms (direct + scatter)
	/////////////////////////////////////////////////////////////////////////

    // vec3 Ab = computeAb(a_b, a_f);
        // vec3 Ab = computeAb(vec3(0.25), vec3(bsdf.density));
        vec3 gi  = vec3(0.0);
    if(bsdf.useScatter) {

        // vec3 sigB = computeBackStrDev(a_b, a_f, b_b, b_f);
        // vec3 sigma2B = sigB * sigB;

        float ix_theta_h = thH * ONE_OVER_PI * 0.5f + 0.5f;
		float ix_theta   = thD   * ONE_OVER_PI_HALF;
		vec3  ix_spread  = sqrt(spread) * ONE_OVER_PI*0.5f;

        gi.r = texture(GItex, vec3(ix_spread.r, ix_theta_h,ix_theta)).r;
        gi.g = texture(GItex, vec3(ix_spread.g, ix_theta_h,ix_theta)).g;
        gi.b = texture(GItex, vec3(ix_spread.b, ix_theta_h,ix_theta)).b;
        // float cosThetaD = cos(thD);
        // float cos2ThetaD = cosThetaD * cosThetaD;

        // float mu = thR + thI;


        // // F Direct Back
        // /////////////////////////////////////////

        // vec3 Gdb = g(mu, sigma2B);
        // fDirectB = (2.0 * Ab * Gdb) / ((PI * cos2ThetaD)) ;

        //  // F Scatter Back
        // /////////////////////////////////////////

        // vec3 Gsb = g(mu, sigma2B + sigma2F);
        // fScatterB = (2.0 * Ab * Gsb) / ((PI * cos2ThetaD)) ; 


    }
     // F Scatter S
    /////////////////////////////////////////
    if(bsdf.useScatter) {

        //Longitudinal
        //-----------------------------------------------

        // float mgRr = g(thH - shifts.x, betas.x + sigma2F.r);
        // float mgRg = g(thH - shifts.x, betas.x + sigma2F.g);
        // float mgRb = g(thH - shifts.x, betas.x + sigma2F.b);
        // float mgTTr = g(thH - shifts.y, betas.y + sigma2F.r);
        // float mgTTg = g(thH - shifts.y, betas.y + sigma2F.g);
        // float mgTTb = g(thH - shifts.y, betas.y + sigma2F.b);
        // float mgTRTr = g(thH - shifts.z, betas.z + sigma2F.r);
        // float mgTRTg = g(thH - shifts.z, betas.z + sigma2F.g);
        // float mgTRTb = g(thH - shifts.z, betas.z + sigma2F.b);

        // vec3 mgR = vec3(mgRr,mgRg,mgRb);
        // vec3 mgTT =vec3(mgTTr,mgTTg,mgTTb);
        // vec3 mgTRT =vec3(mgTRTr,mgTRTg,mgTRTb);

        // //Azimuthal
        // //-----------------------------------------------

        // vec4 ngSample0 = texture(ngTex,vec2(phi * ONE_OVER_PI, abs(thD * ONE_OVER_PI_HALF)));
        // vec3 ngSample1 = texture(ngtTex,vec2(phi * ONE_OVER_PI,abs(thD * ONE_OVER_PI_HALF))).rgb;

        // vec3 ngR = ngSample0.aaa;
        // vec3 ngTT = ngSample0.rgb;
        // vec3 ngTRT = ngSample1;

        // vec3 Rg = r ? mgR * ngR : vec3(0.0);
        // vec3 TTg = tt ? mgTT * ngTT : vec3(0.0);
        // vec3 TRTg = trt ? mgTRT * ngTRT : vec3(0.0);

        // fScatterS = bsdf.density * (transDirect - directFraction) * gi + (Rg * bsdf.Rpower + TTg * bsdf.TTpower + TRTg * bsdf.TRTpower);

    }

    //////////////////////////////////////////////////////////////////////////
	// Build lobes
	////////////////////////////////////////////////////////////////////////

    fDirect = directFraction * (fDirectS + bsdf.density * gi);
    fScatter = vec3(0.0);
    // fScatter = fScatterS;

    color = (fDirect + fScatter);

	//////////////////////////////////////////////////////////////////////////
     return color * li;

}