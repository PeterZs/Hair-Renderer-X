
// robust voxelization kernel for hair segments using 3D DDA traversal (Digital Differential Analyzer)

#version 460
#extension GL_EXT_shader_atomic_float : require

#include utils.glsl
#include object.glsl  // for object.minCoord / object.maxCoord

// Input buffer: one entry per hair segment
struct HairSegment {
    vec3 p0;
    vec3 p1;
    float thickness;
};

layout(std430, set = 0, binding = 0) readonly buffer HairBuffer {
    HairSegment segments[];
};

// Output voxel grid
layout(r32f, set = 0, binding = 1) uniform image3D voxelImage;

void main() {
    uint segID = gl_GlobalInvocationID.x;
    if (segID >= segments.length()) return;

    vec3 p0 = segments[segID].p0;
    vec3 p1 = segments[segID].p1;

    // Map to voxel space [0, gridSize)
    ivec3 gridSize = imageSize(voxelImage);
    vec3 a = mapToZeroOne(p0, object.minCoord.xyz, object.maxCoord.xyz) * vec3(gridSize);
    vec3 b = mapToZeroOne(p1, object.minCoord.xyz, object.maxCoord.xyz) * vec3(gridSize);

    // DDA setup
    ivec3 voxel = ivec3(floor(a));
    ivec3 endVoxel = ivec3(floor(b));
    vec3 rayDir = b - a;
    vec3 step = sign(rayDir);
    vec3 tMax = ((vec3(voxel) + step * 0.5) - a) / rayDir;
    vec3 tDelta = step / rayDir;

    int maxSteps = int(max(gridSize.x, max(gridSize.y, gridSize.z)) * 2);

    for (int i = 0; i < maxSteps; ++i) {
        // Accumulate density
        imageAtomicAdd(voxelImage, clamp(voxel, ivec3(0), gridSize - 1), 1.0);

        // Exit condition
        if (all(equal(voxel, endVoxel))) break;

        // Step to next voxel
        if (tMax.x < tMax.y) {
            if (tMax.x < tMax.z) {
                voxel.x += int(step.x);
                tMax.x += tDelta.x;
            } else {
                voxel.z += int(step.z);
                tMax.z += tDelta.z;
            }
        } else {
            if (tMax.y < tMax.z) {
                voxel.y += int(step.y);
                tMax.y += tDelta.y;
            } else {
                voxel.z += int(step.z);
                tMax.z += tDelta.z;
            }
        }
    }
}
