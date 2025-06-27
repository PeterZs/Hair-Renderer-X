#include "engine/core/materials/hair.h"

VULKAN_ENGINE_NAMESPACE_BEGIN

namespace Core {

Graphics::MaterialUniforms HairMaterial::get_uniforms() const {
    // Alignment in shader
    //-----------------
    // vec3 sigma_a;
    // float thickness;

    // float beta;
    // float shift;
    // float ior;
    // float density;

    // float Rpower;
    // float TTpower;
    // float TRTpower;
    // bool scatter;

    // float azRoughness
    //  bool r;
    //  bool tt;
    //  bool trt;

    //-----------------

    auto deg2rad = [](float deg) { return deg / 180.0 * 3.14159265358979323846; };

    Graphics::MaterialUniforms uniforms;
    uniforms.dataSlot1 = Vec4(m_sigma_a, m_thickness);
    uniforms.dataSlot2 = {deg2rad(m_roughness), deg2rad(m_shift), m_ior, m_density};
    uniforms.dataSlot3 = {m_Rpower, m_TTpower, m_TRTpower, 1.0f};
    uniforms.dataSlot4 = {m_azRoughness, m_R, m_TT, m_TRT};

    return uniforms;
}

} // namespace Core

VULKAN_ENGINE_NAMESPACE_END
