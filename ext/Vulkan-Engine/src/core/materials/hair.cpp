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
    uniforms.dataSlot3 = {m_Rpower, m_TTpower, m_TRTpower, m_useScatter};
    uniforms.dataSlot4 = {m_azRoughness, m_R, m_TT, m_TRT};

    return uniforms;
}

Graphics::MaterialUniforms HairEpicMaterial::get_uniforms() const {
    // Alignment in shader
    //-----------------
    // vec3  baseColor;
    // float thickness;

    // float roughness;
    // float metallic;
    // float specular;
    // float shift;

    // float ior;
    // float Rpower;
    // float TTpower;
    // float TRTpower;

    // float opaqueVisibility;
    // bool  useLegacyAbsorption;
    // bool  useSeparableR;
    // bool  useBacklit;

    // bool clampBSDFValue;
    //  float r;
    // float tt;
    // float trt;
    // float SCATTER;

    //-----------------
    auto deg2rad = [](float deg) { return deg / 180.0 * 3.14159265358979323846; };

    Graphics::MaterialUniforms uniforms;
    uniforms.dataSlot1 = {m_baseColor, m_thickness};
    uniforms.dataSlot2 = {m_roughness, m_metallic, m_specular, deg2rad(m_shift)};
    uniforms.dataSlot3 = {m_ior, m_Rpower, m_TTpower, m_TRTpower};
    uniforms.dataSlot4 = {0.0, m_useLegacyAbsorption, m_useSeparableR, m_useBacklit};
    uniforms.dataSlot5 = {m_clampBSDFValue, m_R, m_TT, m_TRT};
    uniforms.dataSlot6 = {m_useScatter, m_densityBoost, 0.0, 0.0};

    return uniforms;
}

} // namespace Core

VULKAN_ENGINE_NAMESPACE_END
