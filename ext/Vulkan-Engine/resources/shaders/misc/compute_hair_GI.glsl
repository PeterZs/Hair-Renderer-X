#shader compute
#version 460
#include BRDFs/hair_BSDF.glsl

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

layout(rgba32f, set = 0, binding = 0) uniform readonly image2D attFront;
layout(rgba32f, set = 0, binding = 1) uniform readonly image2D attBack;
layout(rgba32f, set = 0, binding = 7) uniform readonly image2D avgBetasFront;
layout(rgba32f, set = 0, binding = 8) uniform readonly image2D avgBetasBack;
layout(rgba32f, set = 0, binding = 9) uniform writeonly image3D outputGI;


void main() {

    // Key Params............................................................

    uint  x         = gl_GlobalInvocationID.x;
    uint  y         = gl_GlobalInvocationID.y;
    uint  z         = gl_GlobalInvocationID.z;
    uvec3 texSize   = imageSize(outputGI);

    if (x >= texSize.x || y >= texSize.y || z >= texSize.z)
        return;


    float spread = float(x) / float(texSize.x - 1) * (2.0 * PI);            //0 to 2PI
    float thH = (float(y)  / float(texSize.y - 1)) * (2.0 * PI) - PI;       // -PI to PI
    float thD = float(z)  / float(texSize.z - 1) * (0.5 * PI);              // 0 to PI/2


    // ............................................................

    float ix_theta = thD * ONE_OVER_PI_HALF;
    // float ix_theta = 0.5;
    int u = int(ix_theta * float(texSize.x - 1));
    vec3 attF = imageLoad(attFront, ivec2(u, 0)).rgb;
    vec3 attB = imageLoad(attBack, ivec2(u, 0)).rgb;
    // vec3 attF = vec3(1.0 - ix_theta,0.0,0.0)*0.6;
    // vec3 attB = vec3(1.0 - ix_theta,0.0,0.0)*0.3;


    vec3 bF = imageLoad(avgBetasFront, ivec2(u, 0)).rgb;
    vec3 bB = imageLoad(avgBetasBack, ivec2(u, 0)).rgb;


    vec3 Ab = computeAb(attB, attF);
    vec3 sigB = computeBackStrDev(attB, attF, bB, bF);
    vec3 sigma2B = sigB * sigB;


    float cosThetaD = cos(thD);
    float cos2ThetaD = cosThetaD * cosThetaD;

    vec3 Gdb = g(thH, vec3(spread*spread+sigma2B));
    // vec3 fBack = (2.0 * Ab * Gdb) / ((PI * cos2ThetaD)) ;
    vec3 fBack = (2.0 * (1.0,1.0,1.0) * Gdb) ;


    imageStore(outputGI, ivec3(x, y, z), vec4(fBack, 1.0));

}
