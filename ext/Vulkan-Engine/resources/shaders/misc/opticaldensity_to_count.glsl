#shader compute
#version 460
//////////////////////////////////////////////////////////////////////////////////////////////////////
// Convert fiber length -> hairCount and density 
//////////////////////////////////////////////////////////////////////////////////////////////////////

layout(local_size_x=8, local_size_y=8, local_size_z=8) in;

// Output voxel grid
layout(set = 0, binding = 6, r32f) uniform image3D voxelLengthImage; // input
layout(set=0,binding=2,r32f) uniform image3D voxelHairCount; // output
// layout(set=0,binding=2,r32f) uniform image3D voxelDensity; // optional

layout(push_constant) uniform ObjectID {
    float meshID;
    float numSegments;
    float avgFiberLength;
} objectID;

void main(){
    ivec3 v = ivec3(gl_GlobalInvocationID.xyz);
    float L = imageLoad(voxelLengthImage, v).r;

    float hairCount = (L / max(objectID.avgFiberLength, 1e-9));
    imageStore(voxelHairCount, v, vec4(hairCount));

    // density = volume fraction if needed: density = (L * crossArea) / voxelVol
    // crossArea = PI * r^2  (r must be provided as a uniform if you want density)
}
