
//////////////////////////////////////////////////////////////////////////////////////////////////////
// Robust voxelization kernel for hair segments using 3D DDA traversal (Digital Differential Analyzer)
//////////////////////////////////////////////////////////////////////////////////////////////////////

#version 460
#extension GL_EXT_shader_atomic_float : require
#include utils.glsl
#include object.glsl  

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;

layout(push_constant) uniform ObjectID {
    vec4 value;
} objectID;

// Output voxel grid
layout(set = 0, binding = 2, r32f) uniform image3D voxelImage;

layout(std430, set = 2, binding = 0) readonly buffer PosBuffers[] {
    vec3 pos[];
};
layout(std430, set = 2, binding = 1) readonly buffer IBOBuffers[] {
    uint indices[];
};

void main() {

    uint meshID = uint(objectID.value.x);   // which mesh in the bindless buffers
    uint segID  = gl_GlobalInvocationID.x;  // segment index = index pair

    // Access the correct VBO + IBO
    vec4 v0 = PosBuffers[meshID].pos[ IBOBuffers[meshID].indices[ segID*2 + 0 ] ];
    vec4 v1 = PosBuffers[meshID].pos[ IBOBuffers[meshID].indices[ segID*2 + 1 ] ];

    vec3 p0 = v0.xyz;
    vec3 p1 = v1.xyz;

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

    for(int i = 0;i < maxSteps;++ i) {
        // Accumulate density
        imageAtomicAdd(voxelImage, clamp(voxel, ivec3(0), gridSize - 1), 1.0);

        // Exit condition
        if(all(equal(voxel, endVoxel))) break;

        // Step to next voxel
        if(tMax.x < tMax.y) {
            if(tMax.x < tMax.z) {
                voxel.x += int(step.x);
                tMax.x += tDelta.x;
            } else {
                voxel.z += int(step.z);
                tMax.z += tDelta.z;
            }
        } else {
            if(tMax.y < tMax.z) {
                voxel.y += int(step.y);
                tMax.y += tDelta.y;
            } else {
                voxel.z += int(step.z);
                tMax.z += tDelta.z;
            }
        }
    }
}
