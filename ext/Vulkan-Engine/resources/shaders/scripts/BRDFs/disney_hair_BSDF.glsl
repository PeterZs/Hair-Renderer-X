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
    vec3 Cg;

    //Intensity
    float Ir;
    float Itt;
    float Itrt;
    float Ig;

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