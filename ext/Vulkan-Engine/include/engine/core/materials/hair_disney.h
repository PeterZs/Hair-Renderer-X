/*
    This file is part of Vulkan-Engine, a simple to use Vulkan based 3D library

    MIT License

    Copyright (c) 2023 Antonio Espinosa Garcia

*/
#ifndef HAIR_D_H
#define HAIR_D_H

#include <engine/core/materials/material.h>
#include <engine/graphics/descriptors.h>
#include <engine/tools/loaders.h>

VULKAN_ENGINE_NAMESPACE_BEGIN

namespace Core {

/// RenderMan's Hair Specification.
class HairDisneyMaterial : public IMaterial
{
  protected:
    // Colors of different scatter events
    Vec3 m_Cr   = {1.0, 1.0, 1.0};
    Vec3 m_Ctt  = {0.6, 0.3, 0.2};
    Vec3 m_Ctrt = {0.6, 0.3, 0.2};
    Vec3 m_Cb   = {0.6, 0.3, 0.2};
    Vec3 m_Cf   = {0.6, 0.3, 0.2};
    // Intensities of different scatter events
    float m_Ir   = 1.0f;
    float m_Itt  = 1.0f;
    float m_Itrt = 1.0f;
    float m_Ig   = 1.0f;
    float m_Ib   = 1.0f;
    float m_If   = 1.0f;
    //
    float m_thickness   = 0.003f;
    float m_roughness   = 0.4f;  //
    float m_azRoughness = 0.35f; // (0 to 1) => perceptually mapped
    float m_shift       = -5.2f; // (-5º to -10º) => -0.088 to -0.17 rads
    float m_ior         = 1.55f;
    float m_density     = 0.7f;
    // Utils
    bool m_R   = true; // Reflection
    bool m_TT  = true; // Transmitance
    bool m_TRT = true; // Second reflection
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

  public:
    HairDisneyMaterial()
        : IMaterial(HAIR_STR_DISNEY_TYPE) {
    }
    HairDisneyMaterial(Vec3 color_tt, Vec3 color_trt, MaterialSettings params = {})
        : IMaterial(HAIR_STR_DISNEY_TYPE, params)
        , m_Ctt(color_tt)
        , m_Ctrt(color_trt) {
    }

    inline Vec3 get_R_color() const {
        return m_Cr;
    }
    inline Vec3 get_TT_color() const {
        return m_Ctt;
    }
    inline Vec3 get_TRT_color() const {
        return m_Ctrt;
    }
    inline Vec3 get_backscatter_color() const {
        return m_Cb;
    }
    inline Vec3 get_frontscatter_color() const {
        return m_Cf;
    }
    inline void set_R_color(Vec3 color) {
        m_Cr      = color;
        m_isDirty = true;
    }
    inline void set_TT_color(Vec3 color) {
        m_Ctt     = color;
        m_isDirty = true;
    }
    inline void set_TRT_color(Vec3 color) {
        m_Ctrt    = color;
        m_isDirty = true;
    }
    inline void set_backscatter_color(Vec3 color) {
        m_Cb      = color;
        m_isDirty = true;
    }
    inline void set_frontscatter_color(Vec3 color) {
        m_Cf      = color;
        m_isDirty = true;
    }
    inline float get_glints_intensity() const {
        return m_Ig;
    }
    inline void set_glints_intensity(float i) {
        m_Ig      = i;
        m_isDirty = true;
    }
    inline float get_frontscatter_intensity() const {
        return m_If;
    }
    inline void set_frontscatter_intensity(float i) {
        m_If      = i;
        m_isDirty = true;
    }
    inline float get_backscatter_intensity() const {
        return m_Ib;
    }
    inline void set_backscatter_intensity(float i) {
        m_Ib      = i;
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
    inline float get_R_intensity() const {
        return m_Ir;
    }
    inline void set_R_intensity(float Rpower) {
        m_Ir      = Rpower;
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
    float get_TT_intensity() const {
        return m_Itt;
    }
    void set_TT_intensity(float TTpower) {
        m_Itt     = TTpower;
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
    inline float get_TRT_intensity() const {
        return m_Itrt;
    }
    inline void set_TRT_intensity(float TRTpower) {
        m_Itrt    = TRTpower;
        m_isDirty = true;
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

} // namespace Core
VULKAN_ENGINE_NAMESPACE_END
#endif