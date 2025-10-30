/*
    This file is part of Vulkan-Engine, a simple to use Vulkan based 3D library

    MIT License

    Copyright (c) 2023 Antonio Espinosa Garcia

*/
#pragma once
#include <engine/core/passes/pass.h>
#include <engine/core/resource_manager.h>

// #define USE_IMG_ATOMIC_OPERATION

VULKAN_ENGINE_NAMESPACE_BEGIN

namespace Core {

#define DDA_VOXELIZATION 0

class HairVoxelizationPass final : public GraphicPass
{

    /*Descriptors*/
    struct FrameDescriptors {
        Graphics::DescriptorSet globalDescritor;
        Graphics::DescriptorSet objectDescritor;
        Graphics::DescriptorSet bufferDescritor;
    };
    std::vector<FrameDescriptors> m_descriptors;

    const uint32_t   MAX_DIRECTIONS = 32;
    Graphics::Buffer m_directionsBuffer;

    void create_voxelization_image();

  public:
    HairVoxelizationPass(Graphics::Device* ctx, uint32_t resolution)
        : BasePass(ctx, {resolution, resolution}, 1, 1, false, "HAIR VOXELIZATION") {
    }

    void setup_attachments(std::vector<Graphics::AttachmentInfo>& attachments, std::vector<Graphics::SubPassDependency>& dependencies) override;

    void setup_uniforms(std::vector<Graphics::Frame>& frames) override;

    void setup_shader_passes() override;

    void render(Graphics::Frame& currentFrame, Scene* const scene, uint32_t presentImageIndex = 0) override;

    void update_uniforms(uint32_t frameIndex, Scene* const scene) override;

    void cleanup() override;
};

} // namespace Core
VULKAN_ENGINE_NAMESPACE_END
