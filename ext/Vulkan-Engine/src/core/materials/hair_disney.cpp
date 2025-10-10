#include "engine/core/materials/hair_disney.h"

VULKAN_ENGINE_NAMESPACE_BEGIN

namespace Core {

Graphics::MaterialUniforms HairDisneyMaterial::get_uniforms() const {
    // Alignment in shader
    //-----------------
    // vec3 Cr;
    // float Ir;

    // vec3 Ctt;
    // float Itt;

    // vec3 Ctrt;
    // float Itrt;

    // vec3 Cg;
    // float Ig;

    // float beta;
    // float shift;
    // float ior;
    // float density;

    // float lambda;
    // float lambfaG
    // float thickness
    // bool scatter;

    //  bool r;
    //  bool tt;
    //  bool trt;

    //-----------------

    auto deg2rad = [](float deg) { return deg / 180.0 * 3.14159265358979323846; };

    Graphics::MaterialUniforms uniforms;
    uniforms.dataSlot1 = Vec4(m_Cr, m_Ir);
    uniforms.dataSlot2 = Vec4(m_Ctt, m_Itt);
    uniforms.dataSlot3 = Vec4(m_Ctrt, m_Itrt);
    uniforms.dataSlot4 = Vec4(m_Cg, m_Ig);
    uniforms.dataSlot5 = {m_roughness, deg2rad(m_shift), m_ior, m_density};
    uniforms.dataSlot6 = {m_azRoughness, m_azRoughness, m_thickness, m_useScatter};
    uniforms.dataSlot7 = {m_R, m_TT, m_TRT, 0.0};

    return uniforms;
}

} // namespace Core

VULKAN_ENGINE_NAMESPACE_END
