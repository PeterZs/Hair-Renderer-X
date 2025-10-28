#shader compute
#version 460
#include object.glsl
#include sh.glsl

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;


layout(set= 0, binding = 3, rgba32f) uniform image3D encodedVolume; // SH0, SH1, SH2, SH3
layout(std430, binding = 4) readonly buffer Directions {
    vec4 directions[];
};
layout(set = 0, binding =5) uniform sampler3D densityVolume;

// // Scene bounds
// layout(push_constant) uniform PushConstants {
//     vec3 volumeMin;
// } params;



float sampleDensity(vec3 pos, ivec3 dim) {
    vec3 uvw = (pos -  object.minCoord.xyz) / ( object.maxCoord.xyz -  object.minCoord.xyz);
    // ivec3 coord = ivec3(clamp(uvw * dim, vec3(0), vec3(dim - 1)));
    // return imageLoad(densityVolume, coord).r;
    return texture(densityVolume, uvw).r;
}

void main() {
    const ivec3 RESOLUTION = textureSize(densityVolume, 0);
    const float STEP_SIZE = 1.0;
    const uint NUM_DIRS = 32;

    ivec3 gid = ivec3(gl_GlobalInvocationID.xyz);
    if (any(greaterThanEqual(gid, RESOLUTION))) return;

    // Compute world-space position of the center of the voxel
    vec3 gridSize = vec3(RESOLUTION);
    vec3 voxelSize = ( object.maxCoord.xyz -  object.minCoord.xyz) / gridSize;
    vec3 voxelCenter =  object.minCoord.xyz + (vec3(gid) + 0.5) * voxelSize;

    // SH L1 accumulator
    vec4 sh = vec4(0.0);

    for (int i = 0; i < NUM_DIRS; ++i) {
        vec3 dir = directions[i].xyz;

        float t = 0.0;
        float densityIntegral = 0.0;
        const float maxDistance = length(object.maxCoord.xyz -  object.minCoord.xyz);

        //Heuristics for controlling ray length
        while (t < maxDistance) {
            vec3 samplePos = voxelCenter + dir * t;
            float d = sampleDensity(samplePos, RESOLUTION);
            densityIntegral += d * STEP_SIZE;
            t += STEP_SIZE;
        }

        // Project into SH L1
        sh += encodeScalarToSHL1(densityIntegral, dir);
    }

    // Normalize
    for (int i = 0; i < 4; ++i) {
        sh[i] /= float(NUM_DIRS);
    }

    imageStore(encodedVolume, gid, sh);
}
