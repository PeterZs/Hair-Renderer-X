/*
    This file is part of Vulkan-Engine, a simple to use Vulkan based 3D library

    MIT License

    Copyright (c) 2023 Antonio Espinosa Garcia

*/
#ifndef HAIR_2_H
#define HAIR_2_H

#include <engine/core/materials/material.h>
#include <engine/graphics/descriptors.h>
#include <engine/tools/loaders.h>

VULKAN_ENGINE_NAMESPACE_BEGIN

namespace Core {

/// Unity's Marschner Workflow. Only works with geometry defined as lines.
class HairMaterial : public IMaterial
{
  protected:
    // Pigment concentrations
    float m_eumelanine   = 1.3f;
    float m_pheomelanine = 0.2f;
    Vec3  m_sigma_a;
    //
    float m_thickness   = 0.003f;
    float m_roughness   = 8.5f;  // (-5º to -10º) => -0.088 to -0.17 rads
    float m_azRoughness = 0.35f; // (0 to 1) => perceptually mapped
    float m_shift       = -5.2f; // (-5º to -10º) => -0.088 to -0.17 rads
    float m_ior         = 1.55f;
    float m_density     = 0.7f;
    // Utils
    bool  m_R        = true; // Reflection
    float m_Rpower   = 4.0f;
    bool  m_TT       = true; // Transmitance
    float m_TTpower  = 2.0f;
    bool  m_TRT      = true; // Second reflection
    float m_TRTpower = 4.0f;
    // Query
    bool m_useScatter      = false;
    bool m_usePigmentation = true;

    std::unordered_map<int, ITexture*> m_textures;
    std::unordered_map<int, bool>      m_textureBindingState;

    virtual Graphics::MaterialUniforms                get_uniforms() const;
    virtual inline std::unordered_map<int, ITexture*> get_textures() const {
        return m_textures;
    }

    virtual std::unordered_map<int, bool> get_texture_binding_state() const {
        return m_textureBindingState;
    }
    virtual void set_texture_binding_state(int id, bool state) {
        m_textureBindingState[id] = state;
    }

    inline void compute_sigma_a() {

        Vec3 eumelaninSigmaA   = {0.419f, 0.697f, 1.37f};
        Vec3 pheomelaninSigmaA = {0.187f, 0.4f, 1.05f};

        m_sigma_a.r = m_eumelanine * eumelaninSigmaA.r + m_pheomelanine * pheomelaninSigmaA.r;
        m_sigma_a.g = m_eumelanine * eumelaninSigmaA.g + m_pheomelanine * pheomelaninSigmaA.g;
        m_sigma_a.b = m_eumelanine * eumelaninSigmaA.b + m_pheomelanine * pheomelaninSigmaA.b;
    }

  public:
    HairMaterial(float eumelanine = 1.3f, float pheomelanine = 0.2f)
        : IMaterial(HAIR_STR_TYPE)
        , m_eumelanine(eumelanine)
        , m_pheomelanine(pheomelanine) {
        compute_sigma_a();
    }
    HairMaterial(float eumelanine, float pheomelanine, MaterialSettings params)
        : IMaterial(HAIR_STR_TYPE, params)
        , m_eumelanine(eumelanine)
        , m_pheomelanine(pheomelanine) {
        compute_sigma_a();
    }

    inline float get_eumelanine() const {
        return m_eumelanine;
    }
    inline void set_eumelanine(float c) {
        if (!m_usePigmentation)
            return;
        m_eumelanine = c;
        compute_sigma_a();
        m_isDirty = true;
    }
    inline float get_pheomelanine() const {
        return m_pheomelanine;
    }
    inline void set_pheomelanine(float c) {
        if (!m_usePigmentation)
            return;
        compute_sigma_a();
        m_pheomelanine = c;
        m_isDirty      = true;
    }

    inline Vec3 get_absorption() {
        return m_sigma_a;
    }
    inline void set_absoption(Vec3 sigma_a) {
        if (m_usePigmentation)
            return;
        m_sigma_a = sigma_a;
        m_isDirty = true;
    }
    inline float get_density() const {
        return m_density;
    }
    inline void set_density(float density) {
        m_density = density;
        m_isDirty = true;
    }

    inline void use_pigmentation(bool op) {
        m_usePigmentation = op;
    }
    inline bool use_pigmentation() {
        return m_usePigmentation;
        m_isDirty = true;
    }
    inline float get_thickness() const {
        return m_thickness;
    }
    inline void set_thickness(float thickness) {
        m_thickness = thickness;
        m_isDirty   = true;
    }

    // Primary reflection toggle
    inline bool get_R() const {
        return m_R;
    }
    inline void set_R(bool R) {
        m_R       = R;
        m_isDirty = true;
    }

    // Primary reflection scale
    inline float get_Rpower() const {
        return m_Rpower;
    }
    inline void set_Rpower(float Rpower) {
        m_Rpower  = Rpower;
        m_isDirty = true;
    }

    // Transmitance reflection toggle
    inline bool get_TT() const {
        return m_TT;
    }
    inline void set_TT(bool TT) {
        m_TT = TT;
    }

    // Transmitance reflection scale
    float get_TTpower() const {
        return m_TTpower;
    }
    void set_TTpower(float TTpower) {
        m_TTpower = TTpower;
        m_isDirty = true;
    }

    // scattering
    inline bool enable_scattering() const {
        return m_useScatter;
    }
    inline void enable_scattering(bool e) {
        m_useScatter = e;
        m_isDirty    = true;
    }
    // Secoundary reflection toggle
    inline bool get_TRT() const {
        return m_TRT;
    }
    inline void set_TRT(bool TRT) {
        m_TRT = TRT;
    }

    // Secoundary reflection scale
    inline float get_TRTpower() const {
        return m_TRTpower;
    }
    inline void set_TRTpower(float TRTpower) {
        m_TRTpower = TRTpower;
        m_isDirty  = true;
    }

    inline float get_roughness() const {
        return m_roughness;
    }
    // In degrees
    void set_roughness(float roughness) {
        m_roughness = roughness;
        m_isDirty   = true;
    }
    inline float get_azimuthal_roughness() const {
        return m_azRoughness;
    }
    // [0 to 1]
    void set_azimuthal_roughness(float roughness) {
        m_azRoughness = roughness;
        m_isDirty     = true;
    }

    // In degrees
    inline float get_shift() const {
        return m_shift;
    }
    inline void set_shift(float shift) {
        m_shift   = shift;
        m_isDirty = true;
    }

    inline float get_ior() const {
        return m_ior;
    }
    inline void set_ior(float ior) {
        m_ior     = ior;
        m_isDirty = true;
    }
};

/// Epic's. Only works with geometry defined as lines.
class HairEpicMaterial : public IMaterial
{
  protected:
    Vec3 m_baseColor = {0.27f, 0.14f, 0.04f};

    float m_thickness = 0.003f;

    bool  m_R        = true; // Reflection
    float m_Rpower   = 1.0f;
    bool  m_TT       = true; // Transmitance
    float m_TTpower  = 1.0f;
    bool  m_TRT      = true; // Second reflection
    float m_TRTpower = 2.0f;

    float m_roughness = 0.4f;
    float m_specular  = 1.0f;
    float m_metallic  = 0.0f;

    float m_shift = 5.2f; // In radians (-5º to -10º) => 0.088 to 0.17 //Not with epic 0.02 does fine
    float m_ior   = 1.55f;

    // Query
    bool m_useSeparableR       = false;
    bool m_useLegacyAbsorption = false;
    bool m_useBacklit          = false;
    bool m_clampBSDFValue      = false;
    bool m_useScatter          = false;

    Geometry* m_skullGeometry = nullptr;

    std::unordered_map<int, ITexture*> m_textures;

    std::unordered_map<int, bool> m_textureBindingState;

    virtual Graphics::MaterialUniforms                get_uniforms() const;
    virtual inline std::unordered_map<int, ITexture*> get_textures() const {
        return m_textures;
    }

    virtual std::unordered_map<int, bool> get_texture_binding_state() const {
        return m_textureBindingState;
    }
    virtual void set_texture_binding_state(int id, bool state) {
        m_textureBindingState[id] = state;
    }

  public:
    HairEpicMaterial(Vec3 baseColor = {0.27f, 0.14f, 0.04f})
        : IMaterial(HAIR_STR_EPIC_TYPE)
        , m_baseColor(baseColor) {
    }
    HairEpicMaterial(Vec3 baseColor, MaterialSettings params)
        : IMaterial(HAIR_STR_EPIC_TYPE, params)
        , m_baseColor(baseColor) {
    }

    inline Vec3 get_base_color() const {
        return m_baseColor;
    }
    inline void set_base_color(Vec3 c) {
        m_baseColor = c;
        m_isDirty   = true;
    }

    float get_thickness() const {
        return m_thickness;
    }
    void set_thickness(float thickness) {
        m_thickness = thickness;
    }

    // Primary reflection toggle
    bool get_R() const {
        return m_R;
    }
    void set_R(bool R) {
        m_R       = R;
        m_isDirty = true;
    }

    // Primary reflection scale
    float get_Rpower() const {
        return m_Rpower;
    }
    void set_Rpower(float Rpower) {
        m_Rpower  = Rpower;
        m_isDirty = true;
    }

    // Transmitance reflection toggle
    bool get_TT() const {
        return m_TT;
    }
    void set_TT(bool TT) {
        m_TT = TT;
    }

    // Transmitance reflection scale
    float get_TTpower() const {
        return m_TTpower;
    }
    void set_TTpower(float TTpower) {
        m_TTpower = TTpower;
        m_isDirty = true;
    }

    // Secoundary reflection toggle
    bool get_TRT() const {
        return m_TRT;
    }
    void set_TRT(bool TRT) {
        m_TRT = TRT;
    }

    // Secoundary reflection scale
    float get_TRTpower() const {
        return m_TRTpower;
    }
    void set_TRTpower(float TRTpower) {
        m_TRTpower = TRTpower;
        m_isDirty  = true;
    }

    float get_roughness() const {
        return m_roughness;
    }
    void set_roughness(float roughness) {
        m_roughness = roughness;
        m_isDirty   = true;
    }
    float get_specular() const {
        return m_specular;
    }
    void set_specular(float spec) {
        m_specular = spec;
        m_isDirty  = true;
    }
    float get_metallic() const {
        return m_metallic;
    }
    void set_metallic(float met) {
        m_metallic = met;
        m_isDirty  = true;
    }

    float get_shift() const {
        return m_shift;
    }
    void set_shift(float shift) {
        m_shift   = shift;
        m_isDirty = true;
    }

    float get_ior() const {
        return m_ior;
    }
    void set_ior(float ior) {
        m_ior     = ior;
        m_isDirty = true;
    }

    bool useSeparableR() const {
        return m_useSeparableR;
    }
    bool useLegacyAbsorption() const {
        return m_useLegacyAbsorption;
    }
    bool useBacklit() const {
        return m_useBacklit;
    }
    bool clampBSDFValue() const {
        return m_clampBSDFValue;
    }

    void setUseSeparableR(bool value) {
        m_useSeparableR = value;
    }
    void setUseLegacyAbsorption(bool value) {
        m_useLegacyAbsorption = value;
    }
    void setUseBacklit(bool value) {
        m_useBacklit = value;
    }
    void setClampBSDFValue(bool value) {
        m_clampBSDFValue = value;
    }

    bool get_useScatter() const {
        return m_useScatter;
    }
    void set_useScatter(bool useScatter) {
        m_useScatter = useScatter;
        m_isDirty    = true;
    }
    void set_skull(Geometry* skullGeometry) {
        m_skullGeometry = skullGeometry;
    };
    Geometry* get_skull() {
        return m_skullGeometry;
    };
};

} // namespace Core
VULKAN_ENGINE_NAMESPACE_END
#endif