#shader vertex
#version 460

#include camera.glsl
#include object.glsl
#include light.glsl
#include utils.glsl

//Input
layout(location = 0) in vec3 pos;

//Output
layout(location = 0) out vec3 v_pos;

layout(set = 1, binding = 1) uniform MaterialUniforms {
    vec4 slot1; 
    vec4 slot2; 
    vec4 slot3; 
    vec4 slot4; 
    vec4 slot5; 
    vec4 slot6; 
    vec4 slot7; 
    vec4 slot8; 
} material;


void main() {

    v_pos = (object.model * vec4(pos, 1.0)).xyz;
    // v_pos = pos;

    vec3 ndc = mapToZeroOne(v_pos, object.minCoord.xyz, object.maxCoord.xyz) ;
    ndc.xy = ndc.xy * 2.0 -1.0; //Because Vulkan
    
    gl_Position = vec4(ndc, 1.0);
    
}

#shader fragment
#version 460
#extension GL_EXT_shader_atomic_float : require
#include object.glsl
#include utils.glsl

#define USE_SPLAT_KERNEL 1

layout(location = 0) in vec3 _pos; // worldspace position of the rasterized hair

layout(set = 0, binding = 2, r32f) uniform image3D voxelImage;

ivec3 worldSpaceToVoxelSpace(vec3 worldPos, out vec3 voxelFloat)
{
    vec3 uvw = mapToZeroOne(worldPos, object.minCoord.xyz, object.maxCoord.xyz);
    
    // voxel float coordinates
    voxelFloat = uvw * vec3(imageSize(voxelImage));

    return ivec3(floor(voxelFloat));
}

void main()
{
    vec3 vposF;
    ivec3 base = worldSpaceToVoxelSpace(_pos, vposF);

#if USE_SPLAT_KERNEL == 1
    vec3 frac = vposF - vec3(base);

    // 8-tap trilinear voxel splat
    for (int dz = 0; dz <= 1; dz++)
    for (int dy = 0; dy <= 1; dy++)
    for (int dx = 0; dx <= 1; dx++)
    {
        ivec3 c = base + ivec3(dx, dy, dz);

        // bounds check
        ivec3 grid = imageSize(voxelImage);
        if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, grid))) continue;

        float wx = (dx == 0) ? (1.0 - frac.x) : frac.x;
        float wy = (dy == 0) ? (1.0 - frac.y) : frac.y;
        float wz = (dz == 0) ? (1.0 - frac.z) : frac.z;
        float w = wx * wy * wz;

        imageAtomicAdd(voxelImage, c, w);
    }

#else
    // nearest voxel fill
    imageAtomicAdd(voxelImage, base, 1.0);
#endif
}
