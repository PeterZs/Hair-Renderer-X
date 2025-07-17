#version 460
layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;

#include "voxel_utils.glsl" // utility functions for raymarching and density

// Input voxelized density volume
layout(set = 0, binding = 2, uimage3D) uniform image3D densityVolume;
// Output SH coefficients
layout(set= 0, binding = 3, rgba32f) uniform image3D encodedVolume; // SH0, SH1, SH2, SH3


// Scene bounds
layout(push_constant) uniform PushConstants {
    vec3 volumeMin;
    vec3 volumeMax;
    ivec3 voxelResolution;
    int numDirections;
    float stepSize;
} params;

// Direction samples (assume 64 directions or so)
layout(std430, binding = 2) readonly buffer Directions {
    vec3 directions[];
};

float sampleDensity(vec3 pos) {
    vec3 uvw = (pos - params.volumeMin) / (params.volumeMax - params.volumeMin);
    ivec3 dim = imageSize(densityVolume);
    ivec3 coord = ivec3(clamp(uvw * dim, vec3(0), vec3(dim - 1)));
    return imageLoad(densityVolume, coord).r;
}

void main() {
    ivec3 gid = ivec3(gl_GlobalInvocationID.xyz);
    if (any(greaterThanEqual(gid, params.voxelResolution))) return;

    // Compute world-space position of the center of the voxel
    vec3 gridSize = vec3(params.voxelResolution);
    vec3 voxelSize = (params.volumeMax - params.volumeMin) / gridSize;
    vec3 voxelCenter = params.volumeMin + (vec3(gid) + 0.5) * voxelSize;

    // SH accumulator
    float sh[4] = { 0.0, 0.0, 0.0, 0.0 };

    for (int i = 0; i < params.numDirections; ++i) {
        vec3 dir = directions[i];

        // Raymarch along dir from voxelCenter
        float t = 0.0;
        float densityIntegral = 0.0;
        const float maxDistance = length(params.volumeMax - params.volumeMin);

        while (t < maxDistance) {
            vec3 samplePos = voxelCenter + dir * t;
            float d = sampleDensity(samplePos);
            densityIntegral += d * params.stepSize;
            t += params.stepSize;
        }

        // Project into SH L1
        const float sh0 = 0.282095;
        const float sh1 = 0.488603 * dir.y;
        const float sh2 = 0.488603 * dir.z;
        const float sh3 = 0.488603 * dir.x;

        sh[0] += densityIntegral * sh0;
        sh[1] += densityIntegral * sh1;
        sh[2] += densityIntegral * sh2;
        sh[3] += densityIntegral * sh3;
    }

    // Normalize
    for (int i = 0; i < 4; ++i) {
        sh[i] /= float(params.numDirections);
    }

    // Store SH as RGBA
    imageStore(shTexture, gid, vec4(sh[0], sh[1], sh[2], sh[3]));
}
