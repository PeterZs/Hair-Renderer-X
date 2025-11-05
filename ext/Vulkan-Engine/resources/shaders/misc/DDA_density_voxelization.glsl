#shader compute
#version 460

//////////////////////////////////////////////////////////////////////////////////////////////////////
// Robust voxelization kernel for hair segments using 3D DDA traversal (Digital Differential Analyzer)
//////////////////////////////////////////////////////////////////////////////////////////////////////
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_shader_atomic_float : require
#include object.glsl  
#include utils.glsl

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;


layout(push_constant) uniform ObjectID {
    float meshID;
    float numSegments;
} objectID;

// Output voxel grid
layout(set = 0, binding = 2, r32f) uniform image3D voxelImage;

layout(std430, set = 2, binding = 0) readonly buffer PosBuffer {
    vec4 pos[];
} posBuffers[];
layout(std430, set = 2, binding = 1) readonly buffer IndexBuffer {
    uint indices[];
} indexBuffers[];

#define AMANATIDES_WOO 1
#define USE_SPLAT_KERNEL 1

void main() {

    uint meshID = nonuniformEXT(uint(objectID.meshID));   // which mesh in the bindless buffers
    uint segID  = gl_GlobalInvocationID.x;  // segment index = index pair
    if(segID >= uint(objectID.numSegments)) return;

    uint i0 = indexBuffers[nonuniformEXT(meshID)].indices[segID * 2u + 0u];
    uint i1 = indexBuffers[nonuniformEXT(meshID)].indices[segID * 2u + 1u];

    // fetch positions (vec4 stored for alignment); take xyz
    vec3 p0 = (object.model * posBuffers[nonuniformEXT(meshID)].pos[i0]).xyz;
    vec3 p1 = (object.model * posBuffers[nonuniformEXT(meshID)].pos[i1]).xyz;

    // Map to voxel-space [0, gridSize)
    ivec3 gridSize = imageSize(voxelImage);
    vec3 a = mapToZeroOne(p0, object.minCoord.xyz, object.maxCoord.xyz) * vec3(gridSize);
    vec3 b = mapToZeroOne(p1, object.minCoord.xyz, object.maxCoord.xyz) * vec3(gridSize);
    a = clamp(a, vec3(0.0), vec3(gridSize - 1));
    b = clamp(b, vec3(0.0), vec3(gridSize - 1));

    // DDA setup (robust against zero components)
    ivec3 voxel = ivec3(floor(a));
    ivec3 endVoxel = ivec3(floor(b));
    vec3 rayDir = b - a;

    // handle degenerate segment (same voxel)
    if (all(equal(voxel, endVoxel))) {
        imageAtomicAdd(voxelImage, clamp(voxel, ivec3(0), gridSize - 1), 1.0);
        return;
    }


#if AMANATIDES_WOO == 0
// SIMPLE STEPPING 
//////////////////////////////////////////////////////////////////////////////////////////////////////

    vec3 step = sign(rayDir);

    // compute safe inverse (avoid divide-by-zero)
    const float BIG = 1e30;
    vec3 inv = vec3(
        (abs(rayDir.x) < 1e-12) ? BIG : (1.0 / rayDir.x),
        (abs(rayDir.y) < 1e-12) ? BIG : (1.0 / rayDir.y),
        (abs(rayDir.z) < 1e-12) ? BIG : (1.0 / rayDir.z)
    );

    // tMax: distance to first voxel boundary along ray in parametric t (in voxel-space)
    vec3 voxelF = vec3(voxel);
    vec3 nextVoxelBoundary = voxelF + (step * 0.5); // halfway to next voxel center
    vec3 tMax = (nextVoxelBoundary - a) * inv;
    // tDelta: how far we must move in t to cross one voxel in each axis
    vec3 tDelta = abs(inv);

    // conservative step limit
    int maxSteps = int(max(gridSize.x, max(gridSize.y, gridSize.z))*2.0);

    for (int iter = 0; iter < maxSteps; ++iter)
    {

#if USE_SPLAT_KERNEL == 1
    vec3 frac = a - voxelF;

    // 8-tap trilinear voxel splat
    for (int dz = 0; dz <= 1; dz++)
    for (int dy = 0; dy <= 1; dy++)
    for (int dx = 0; dx <= 1; dx++)
    {
        ivec3 c = base + ivec3(dx, dy, dz);

        // bounds check
        if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, gridSize))) continue;

        float wx = (dx == 0) ? (1.0 - frac.x) : frac.x;
        float wy = (dy == 0) ? (1.0 - frac.y) : frac.y;
        float wz = (dz == 0) ? (1.0 - frac.z) : frac.z;
        float w = wx * wy * wz;

        imageAtomicAdd(voxelImage, c, w);
    }

#else
        // accumulate (uint counter)
        imageAtomicAdd(voxelImage, clamp(voxel, ivec3(0), gridSize - 1), 1.0);
#endif

        if (all(equal(voxel, endVoxel))) break;

        // advance to next voxel
        if (tMax.x < tMax.y)
        {
            if (tMax.x < tMax.z)
            {
                voxel.x += int(step.x);
                tMax.x += tDelta.x;
            }
            else
            {
                voxel.z += int(step.z);
                tMax.z += tDelta.z;
            }
        }
        else
        {
            if (tMax.y < tMax.z)
            {
                voxel.y += int(step.y);
                tMax.y += tDelta.y;
            }
            else
            {
                voxel.z += int(step.z);
                tMax.z += tDelta.z;
            }
        }
    }

    #else
//  // Amanatides & Woo DDA
//////////////////////////////////////////////////////////////////////////////////////////////////////

   
    vec3 direction = b - a;
    vec3 dir = direction;        
    vec3 step = sign(direction);
    // compute tMax and tDelta robustly:
    // For each axis:
    // if dir>0: tMax = ( (floor(a)+1) - a ) / dir
    // else:     tMax = ( a - floor(a) ) / -dir
    // tDelta = 1 / abs(dir)
    const float INF = 1e30;
    vec3 tMax;
    vec3 tDelta;
    // X
    if (abs(dir.x) < 1e-12) {
        tMax.x = INF;
        tDelta.x = INF;
    } else {
        if (dir.x > 0.0)
            tMax.x = ( (float(voxel.x) + 1.0) - a.x ) / dir.x;
        else
            tMax.x = ( a.x - float(voxel.x) ) / (-dir.x);
        tDelta.x = 1.0 / abs(dir.x);
    }
    // Y
    if (abs(dir.y) < 1e-12) {
        tMax.y = INF;
        tDelta.y = INF;
    } else {
        if (dir.y > 0.0)
            tMax.y = ( (float(voxel.y) + 1.0) - a.y ) / dir.y;
        else
            tMax.y = ( a.y - float(voxel.y) ) / (-dir.y);
        tDelta.y = 1.0 / abs(dir.y);
    }
    // Z
    if (abs(dir.z) < 1e-12) {
        tMax.z = INF;
        tDelta.z = INF;
    } else {
        if (dir.z > 0.0)
            tMax.z = ( (float(voxel.z) + 1.0) - a.z ) / dir.z;
        else
            tMax.z = ( a.z - float(voxel.z) ) / (-dir.z);
        tDelta.z = 1.0 / abs(dir.z);
    }

    int maxSteps = int(max(gridSize.x, max(gridSize.y, gridSize.z)) * 4);
    for (int s = 0; s < maxSteps; ++s) {
        imageAtomicAdd(voxelImage, clamp(voxel, ivec3(0), gridSize - 1), 1.0);
        if (all(equal(voxel, endVoxel))) break;

        // step the axis with smallest tMax
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

    #endif
}
