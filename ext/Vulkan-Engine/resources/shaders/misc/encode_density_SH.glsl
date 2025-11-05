#shader compute
#version 460
#include object.glsl
#include sh.glsl

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

layout(set = 0, binding = 3, rgba32f) uniform image3D encodedVolume; 
layout(std430, binding = 4) readonly buffer Directions {
    vec4 directions[];
};
layout(set = 0, binding = 5) uniform sampler3D densityVolume; 

#define USE_AMANATIDES_WOO_DDA 1

float sampleDensity(vec3 pos)
{
    vec3 uv = (pos - object.minCoord.xyz) / (object.maxCoord.xyz - object.minCoord.xyz);
    return texture(densityVolume, uv).r;
}

bool insideBounds(ivec3 v, ivec3 dim) {
    return !any(lessThan(v, ivec3(0))) && !any(greaterThanEqual(v, dim));
}

void main()
{
    ivec3 dim = textureSize(densityVolume, 0);
    ivec3 gid = ivec3(gl_GlobalInvocationID.xyz);
    if (!insideBounds(gid, dim)) return;

    vec3 boundsMin = object.minCoord.xyz;
    vec3 boundsMax = object.maxCoord.xyz;

    vec3 gridSize = vec3(dim);
    vec3 voxelSize = (boundsMax - boundsMin) / gridSize;
    vec3 voxelCenter = boundsMin + (vec3(gid) + 0.5) * voxelSize;

    // If empty voxel, skip
    if (sampleDensity(voxelCenter) == 0.0) return;

    vec4 sh = vec4(0.0);
    const uint NUM_DIRS = 32;

    for (uint d = 0; d < NUM_DIRS; d++)
    {
        vec3 dir = normalize(directions[d].xyz);
        float accum = 0.0;

#if USE_AMANATIDES_WOO_DDA == 1

        // --- Build ray start/end inside volume ---
        vec3 rayOrigin = voxelCenter;
        vec3 rayEnd = rayOrigin + dir * length(boundsMax - boundsMin);

        // Convert to voxel space
        vec3 startV = (rayOrigin - boundsMin) / (boundsMax - boundsMin) * gridSize;
        vec3 endV   = (rayEnd    - boundsMin) / (boundsMax - boundsMin) * gridSize;

        ivec3 voxel = ivec3(floor(startV));
        ivec3 target = ivec3(floor(endV));

        vec3 tMax, tDelta;
        vec3 rayDir = normalize(endV - startV);
        ivec3 step = ivec3(sign(rayDir));

        for (int axis = 0; axis < 3; axis++)
        {
            if (abs(rayDir[axis]) < 1e-6)
            {
                tMax[axis] = 1e30;
                tDelta[axis] = 1e30;
            }
            else
            {
                float nextBoundary = (step[axis] > 0) ?
                    (float(voxel[axis] + 1) - startV[axis]) :
                    (startV[axis] - float(voxel[axis]));

                tMax[axis] = nextBoundary / abs(rayDir[axis]);
                tDelta[axis] = 1.0 / abs(rayDir[axis]);
            }
        }

        int maxSteps = int(gridSize.x + gridSize.y + gridSize.z);

        for (int s = 0; s < maxSteps; s++)
        {
            if (!insideBounds(voxel, dim)) break;

            vec3 worldPos = boundsMin + (vec3(voxel) + 0.5) * voxelSize;
            accum += sampleDensity(worldPos);

            // advance voxel
            if (tMax.x < tMax.y)
            {
                if (tMax.x < tMax.z) { voxel.x += step.x; tMax.x += tDelta.x; }
                else                 { voxel.z += step.z; tMax.z += tDelta.z; }
            }
            else
            {
                if (tMax.y < tMax.z) { voxel.y += step.y; tMax.y += tDelta.y; }
                else                 { voxel.z += step.z; tMax.z += tDelta.z; }
            }

            if (voxel == target) break;
        }

#else
        // Fallback uniform stepping (for debug)
        float t = 0.0;
        float maxT = length(boundsMax - boundsMin);
        while (t < maxT) {
            accum += sampleDensity(voxelCenter + dir * t);
            t += length(voxelSize);
        }
#endif

        // SH L1 projection
        sh += encodeScalarToSHL1(accum, dir);
    }

    sh /= float(NUM_DIRS);
    imageStore(encodedVolume, gid, sh);
}
