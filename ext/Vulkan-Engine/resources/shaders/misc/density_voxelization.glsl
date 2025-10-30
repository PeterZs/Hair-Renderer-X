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
#extension GL_EXT_shader_atomic_float  : require
#include object.glsl
#include utils.glsl


layout(location = 0) in vec3 _pos;


layout(set = 0,  binding =  2, r32f) uniform image3D               voxelImage;

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

ivec3 worldSpaceToVoxelSpace(vec3 worldPos)
{
    vec3 uvw = mapToZeroOne(worldPos, object.minCoord.xyz, object.maxCoord.xyz);
    ivec3 voxelPos = ivec3(uvw * imageSize(voxelImage));
    return voxelPos;
}


void main() {

    ivec3 voxelPos = worldSpaceToVoxelSpace(_pos);

    float ocupancy = 1.0;
    imageAtomicAdd(voxelImage, voxelPos, ocupancy);

}
