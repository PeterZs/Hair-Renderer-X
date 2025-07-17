#pragma once
#include <engine/core/passes/pass.h>
#include <engine/core/resource_manager.h>

VULKAN_ENGINE_NAMESPACE_BEGIN

namespace Core {

class HairScatteringPass : public ComputePass
{
    struct FrameDescriptors {
        Graphics::DescriptorSet globalDescritor;
        Graphics::DescriptorSet objectDescritor;
    };
    std::vector<FrameDescriptors> m_descriptors;


    void create_hair_scattering_images();

  public:
    HairScatteringPass(Graphics::Device* ctx, uint32_t extent)
        : BasePass(ctx, {extent, extent}, 1, 1, false, "HAIR SCATTERING") {
            
    }

    void setup_attachments(std::vector<Graphics::AttachmentInfo>& attachments, std::vector<Graphics::SubPassDependency>& dependencies);

    void setup_uniforms(std::vector<Graphics::Frame>& frames);

    void setup_shader_passes();

    void render(Graphics::Frame& currentFrame, Scene* const scene, uint32_t presentImageIndex = 0);

    void cleanup();
};

} // namespace Core
VULKAN_ENGINE_NAMESPACE_END
