/////////////////////////////////////////////
// LUT BASED
/////////////////////////////////////////////

#ifndef PI 
#define PI              3.1415926535897932384626433832795
#endif
#define ONE_OVER_PI      (1.0 / PI)
#define ONE_OVER_PI_HALF (2.0 / PI)
#define DEG2RAD(x) ((x) / 180.0 * PI)
#define R_SHIFT      DEG2RAD(-7.0)
#define TT_SHIFT     (-R_SHIFT*0.5)
#define TRT_SHIFT    (-R_SHIFT*1.5)
#define R_DEV        DEG2RAD(10.0)
#define TT_DEV       DEG2RAD(10.0)
#define TRT_DEV      DEG2RAD(18.0)
#define ECCEN_SHIFT  DEG2RAD(25.0)

// #define SCALE_N_R      0.25
// #define SCALE_N_TT     0.5
// #define SCALE_N_TRT    0.25
#define SCALE_N_R      1.85669
#define SCALE_N_TT     2.13384
#define SCALE_N_TRT    2.13384

#define GLOBAL_SCALE    5.0
#define DENSITY_SCALE   10000.0
#define DENSITY         0.7


struct                          MarschnerLookupBSDF{
    vec3                        tangent;
    float                       Rpower;
    float                       TTpower;
    float                       TRTpower;
    float                       density;
};

//Longitudinal TERM (Gaussian Distribution)
float M(float x_mu, float beta) {
    return exp(-0.5*x_mu*x_mu/(beta*beta))/(sqrt(2.0*PI)*beta);
}

//Rand generator
float rand( int n, int seed )
{
	n = (n<<13) ^ (n+seed);
	n = (n * (n * n * 15731 + 789221) + 1376312589) + n;
	return float(n & 0x7fffffff) / 2147483648.0;
}
//////////////////////////////////////////////////////////////////////////
// Spetial shadow mapping for hair for controlling density
//////////////////////////////////////////////////////////////////////////
float bilinear( float v[4], vec2 f )
	{
		return mix( mix( v[0], v[1], f.x ), mix( v[2], v[3], f.x ), f.y );
	}

vec3 bilinear( vec3 v[4], vec2 f )
	{
		return mix( mix( v[0], v[1], f.x ), mix( v[2], v[3], f.x ), f.y );
	}    
vec3 hairShadow( out vec3 spread, out float directF, vec3 pShad, sampler2DArray shadowMap, int lightId, float density)
	{
		ivec2 size = textureSize( shadowMap, 0 ).xy;
		vec2 t = pShad.xy * vec2(size) + 0.5;
		vec2 f = t - floor(t);
		vec2 s = 0.5 / vec2(size);
		
		vec2 tcp[4];
		tcp[0] = pShad.xy + vec2( -s.x, -s.y );
		tcp[1] = pShad.xy + vec2(  s.x, -s.y );
		tcp[2] = pShad.xy + vec2( -s.x,  s.y );
		tcp[3] = pShad.xy + vec2(  s.x,  s.y );

		const float coverage = 0.05;
		const vec3 a_f = vec3( 0.507475266, 0.465571405, 0.394347166 );
		const vec3 w_f = vec3( 0.028135575, 0.027669785, 0.027669785 );
		float dir[4];
		vec3 spr[4], t_d[4];
		for ( int i=0; i<4; ++i ) {
			float z = texture(shadowMap, vec3(tcp[i],lightId)).r;
			float h = max( 0.0, pShad.z - z );
			float n = h * density * DENSITY_SCALE;
			dir[i] = pow( 1.0 - coverage, n );
			t_d[i] = pow( 1.0 - coverage*(1.0 - a_f), vec3(n,n,n) );
			spr[i] = n * coverage * w_f;
		}
		
		directF = bilinear( dir, f );
		spread  = bilinear( spr, f );
		return    bilinear( t_d, f );
	}

vec3 computeHairShadow(LightUniform light,int lightId, sampler2DArray shadowMap, float density, vec3 pos, out vec3 spread, out float directF )
	{
        vec4 posLightSpace = light.viewProj * vec4(pos, 1.0);
        vec3 projCoords = posLightSpace.xyz / posLightSpace.w; 
        projCoords.xy = projCoords.xy * 0.5 + 0.5;
       
		vec3 transDirect = hairShadow( spread, directF, projCoords,shadowMap, lightId,density );
		directF *= 0.5;
		return transDirect * 0.5;
	}    


vec3 evalMarschnerLookupBSDF(
    vec3 wi,               //Light vector
    vec3 v,                //View vector
    vec3 irradiance,
    MarschnerLookupBSDF bsdf,
	sampler2D texM,
    sampler2D texN,
    sampler2D texNTRT,
    sampler3D texGI,
    sampler2D texGI_M,
    sampler2D texGI_N,
    sampler2D texGI_NTRT,
    vec3 transDirect,
    vec3 spread,
    float directFraction,
    bool r,
    bool tt, 
    bool trt,
	bool scatter) 
    {

    //Theta
    vec3 u              = bsdf.tangent;
    float sin_thI      = dot(wi, u);
    float thI           = asin(sin_thI);
    float sin_thR       = dot(v, u);
    float thR           = asin(sin_thR);

    float thH           = thR + thI;

    float th            = 0.5 * abs(thR - thI);
    float ix_th         = th  * ONE_OVER_PI_HALF;

    //Phi   
    vec3 wiPerp         = normalize(wi - sin_thI * u);
    vec3 vPerp          = normalize(v - sin_thR * u);
    float cos_phiH      = dot( wiPerp, vPerp );
	float phiH          = acos( cos_phiH );
	float cos_phiD = dot(wiPerp,vPerp)*pow(dot(wiPerp,wiPerp)*dot(vPerp,vPerp),-0.5);

    float randVal = rand( 2, 3 );
	float phi_shift = ECCEN_SHIFT*(randVal-0.5f);
	float phiTRT = abs( phiH + phi_shift );
	if ( phiTRT > 2.0*PI ) phiTRT -= 2.0*PI;
	if ( phiTRT > PI ) phiTRT = 2.0*PI - phiTRT;

    //////////////////////////////////////////////////////////////////////////
	// Direct Illumination
	//////////////////////////////////////////////////////////////////////////

    // N
    vec2 index1         = vec2( phiH * ONE_OVER_PI, 1-ix_th );
	vec2 index2         = vec2( phiH * ONE_OVER_PI, 1-ix_th );
	float cosThetaL = sqrt(max(0, 1 - sin_thI * sin_thI));
	float cosThetaV = sqrt(max(0, 1 - sin_thR * sin_thR));
	float CosThetaD = sqrt((1 + cosThetaL * cosThetaV + sin_thR * sin_thI) / 2.0);
	// vec2 index3         = vec2( (cos_phiD*0.5+0.5),(CosThetaD*0.5+0.5) );
	// vec2 index3         = vec2( (cos_phiD*0.5+0.5),sin_thR*0.5+0.5 );
	// vec2 index3         = vec2( clamp(cos_phiD*0.5+0.5,0.01,0.99),clamp((CosThetaD*0.5+0.5),0.01,0.99));

	vec2 indexM 		= vec2(sin_thI*0.5+0.5,sin_thR*0.5+0.5  );
	vec2 indexN       	= vec2( clamp(cos_phiD*0.5+0.5,0.01,0.99),clamp((sin_thR*0.5+0.5),0.01,0.99));

	// vec2 indexM 		= vec2( thI , thR );

    vec4  N             = texture( texN, indexN );
    // float  NR             = texture(texN, vec2(index3.x,  dot(wi,v)*0.5+0.5)).a;
	float NR            = SCALE_N_R   * N.a;
	vec3  NTT           = SCALE_N_TT  * N.rgb;
	vec3  NTRT          = SCALE_N_TRT * texture( texNTRT, indexN ).rgb;

    // M

	float MR            = texture(texM,indexM).r*11.2733;
	float MTT           = texture(texM,indexM).g*38.8877;
	float MTRT          = texture(texM,indexM).b*2.96249;

    float R             = r ?   MR   *	NR   *  bsdf.Rpower  : 0.0; 
    vec3 TT             = tt ?  MTT  * 	NTT  *  bsdf.TTpower  : vec3(0.0); 
    vec3 TRT            = trt ? MTRT * 	NTRT *  bsdf.TRTpower: vec3(0.0); 

    vec3 color          = R+TT+TRT;
    // vec3 color          = vec3(index3,0.0);

	if(scatter){
    //////////////////////////////////////////////////////////////////////////
	// Local Scattering
	//////////////////////////////////////////////////////////////////////////

    float ix_thH = thH * ONE_OVER_PI * 0.5 + 0.5;
    vec3  ix_spread  =  sqrt(spread) * ONE_OVER_PI* 0.5;

	vec3 gi;
	gi.r = DENSITY * texture( texGI, vec3( ix_spread.r, 1-ix_thH, ix_th ) ).r;
	gi.g = DENSITY * texture( texGI, vec3( ix_spread.g, 1-ix_thH, ix_th ) ).g;
	gi.b = DENSITY * texture( texGI, vec3( ix_spread.b, 1-ix_thH, ix_th ) ).b;

	color += gi;
	color *= directFraction;

    //////////////////////////////////////////////////////////////////////////
	// Global Scattering
	//////////////////////////////////////////////////////////////////////////

	vec3 trans = transDirect - directFraction;

	//N
	vec4  N_GI 		= texture(texGI_N, index1 );
	float NR_GI   	= N_GI.a;
	vec3  NTT_GI  	= N_GI.rgb;
	vec3  NTRT_GI 	= texture(texGI_NTRT, index2 ).rgb;

	//M
	vec3 M_GIr 		= texture(texGI_M, vec2(ix_spread.r, 1-ix_thH) ).xyz;
	vec3 M_GIg 		= texture(texGI_M, vec2(ix_spread.g, 1-ix_thH) ).xyz;
	vec3 M_GIb 		= texture(texGI_M, vec2(ix_spread.b, 1-ix_thH) ).xyz;

	vec3 MR_GI   	= vec3( M_GIr.x, M_GIg.x, M_GIb.x );
	vec3 MTT_GI  	= vec3( M_GIr.y, M_GIg.y, M_GIb.y );
	vec3 MTRT_GI 	= vec3( M_GIr.z, M_GIg.z, M_GIb.z );

	vec3 f_indir = trans * DENSITY * ( gi + MR_GI*NR_GI + MTT_GI*NTT_GI + MTRT_GI*NTRT_GI );	// N components already divided by PI
	color +=  f_indir;
	
	// color += gi * 0.1; 
	}
	//////////////////////////////////////////////////////////////////////////

    return              color * irradiance * GLOBAL_SCALE;
    // return              color ;
}
// vec3 evalMarschnerLookupBSDF(
//     vec3 wi,               //Light vector
//     vec3 v,                //View vector
//     vec3 irradiance,
//     MarschnerLookupBSDF bsdf,
// 	sampler2D texM,
//     sampler2D texN,
//     sampler2D texNTRT,
//     sampler3D texGI,
//     sampler2D texGI_M,
//     sampler2D texGI_N,
//     sampler2D texGI_NTRT,
//     vec3 transDirect,
//     vec3 spread,
//     float directFraction,
//     bool r,
//     bool tt, 
//     bool trt,
// 	bool scatter) 
//     {

//     //Theta
//     vec3 u              = bsdf.tangent;
//     float sin_thI      = dot(wi, u);
//     float thI           = asin(sin_thI);
//     float sin_thR       = dot(v, u);
//     float thR           = asin(sin_thR);

//     float thH           = thR + thI;

//     float th            = 0.5 * abs(thR - thI);
//     float ix_th         = th  * ONE_OVER_PI_HALF;

//     //Phi   
//     vec3 wiPerp         = normalize(wi - sin_thI * u);
//     vec3 vPerp          = normalize(v - sin_thR * u);
//     float cos_phiH      = dot( wiPerp, vPerp );
// 	float phiH          = acos( cos_phiH );
// 	float cos_phiD = dot(wiPerp,vPerp)*pow(dot(wiPerp,wiPerp)*dot(vPerp,vPerp),-0.5);

//     //////////////////////////////////////////////////////////////////////////
// 	// Local Scattering
// 	//////////////////////////////////////////////////////////////////////////

// float indexBack 	=  sin_thI * 0.5 + 0.5;
// vec3 Ab 			= texture(AbText, indexBack);
// vec3 spreadMean 	= texture(meanText, indexBack);
// vec3 spreadDev 		= texture(devText, indexBack);


// vec3 fBack = 2.0 * Ab * M(th + thR - spreadMean, spreadDev + spread)/(PI * cos(th) * cos(th)); 

//     //////////////////////////////////////////////////////////////////////////
// 	// Direct Illumination
// 	//////////////////////////////////////////////////////////////////////////

//     // N


// 	vec2 indexM 		= vec2(sin_thI*0.5+0.5,sin_thR*0.5+0.5  );
// 	vec2 indexN       	= vec2( clamp(cos_phiD*0.5+0.5,0.01,0.99),clamp((sin_thR*0.5+0.5),0.01,0.99));

//     vec4  N             = texture( texN, indexN );
// 	float NR            = SCALE_N_R   * N.a;
// 	vec3  NTT           = SCALE_N_TT  * N.rgb;
// 	vec3  NTRT          = SCALE_N_TRT * texture( texNTRT, indexN ).rgb;

//     // M

// 	float MR            = texture(texM,indexM).r*11.2733;
// 	float MTT           = texture(texM,indexM).g*38.8877;
// 	float MTRT          = texture(texM,indexM).b*2.96249;

//     float R             = r ?   MR   *	NR   *  bsdf.Rpower  : 0.0; 
//     vec3 TT             = tt ?  MTT  * 	NTT  *  bsdf.TTpower  : vec3(0.0); 
//     vec3 TRT            = trt ? MTRT * 	NTRT *  bsdf.TRTpower: vec3(0.0); 

//     vec3 fDirect 		= R+TT+TRT;
//     vec3 color          = (fDirect + 0.7 * fBack) * directFraction;
//     // vec3 color          = vec3(index3,0.0);

// 	if(scatter){

//     //////////////////////////////////////////////////////////////////////////
// 	// Global Scattering
// 	//////////////////////////////////////////////////////////////////////////

// 	vec3 trans = transDirect - directFraction;

// 	//N
// 	vec4  N_GI 		= texture(texGI_N, index1 );
// 	float NR_GI   	= N_GI.a;
// 	vec3  NTT_GI  	= N_GI.rgb;
// 	vec3  NTRT_GI 	= texture(texGI_NTRT, index2 ).rgb;

// 	//M
// 	vec3 M_GIr 		= texture(texGI_M, vec2(ix_spread.r, 1-ix_thH) ).xyz;
// 	vec3 M_GIg 		= texture(texGI_M, vec2(ix_spread.g, 1-ix_thH) ).xyz;
// 	vec3 M_GIb 		= texture(texGI_M, vec2(ix_spread.b, 1-ix_thH) ).xyz;

// 	vec3 MR_GI   	= vec3( M_GIr.x, M_GIg.x, M_GIb.x );
// 	vec3 MTT_GI  	= vec3( M_GIr.y, M_GIg.y, M_GIb.y );
// 	vec3 MTRT_GI 	= vec3( M_GIr.z, M_GIg.z, M_GIb.z );

// 	vec3 f_indir = trans * DENSITY * ( gi + MR_GI*NR_GI + MTT_GI*NTT_GI + MTRT_GI*NTRT_GI );	// N components already divided by PI
// 	color +=  f_indir;
	
// 	// color += gi * 0.1; 
// 	}
// 	//////////////////////////////////////////////////////////////////////////

//     return              color * irradiance * GLOBAL_SCALE;
//     // return              color ;
// }


