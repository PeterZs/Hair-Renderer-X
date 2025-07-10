#include <engine/core/passes/hair_scattering_pass.h>

VULKAN_ENGINE_NAMESPACE_BEGIN
using namespace Graphics;
namespace Core {

void HairScatteringPass::create_hair_scattering_images() {
    m_backAtt.cleanup();

    ImageConfig config = {};
    config.viewType    = TEXTURE_2D;
    config.format      = SRGBA_32F;
    config.usageFlags  = IMAGE_USAGE_SAMPLED | IMAGE_USAGE_TRANSFER_DST | IMAGE_USAGE_TRANSFER_SRC | IMAGE_USAGE_STORAGE;
    config.mipLevels   = 1;
    m_backAtt          = m_device->create_image({m_imageExtent.width, 1, 1}, config, false);
    m_backAtt.create_view(config);

    SamplerConfig samplerConfig      = {};
    samplerConfig.samplerAddressMode = ADDRESS_MODE_CLAMP_TO_BORDER;
    samplerConfig.border             = BorderColor::FLOAT_OPAQUE_BLACK;
    m_backAtt.create_sampler(samplerConfig);

    m_frontAtt.cleanup();
    m_frontAtt = m_device->create_image({m_imageExtent.width, 1, 1}, config, false);
    m_frontAtt.create_view(config);
    m_frontAtt.create_sampler(samplerConfig);
}
void HairScatteringPass::setup_attachments(std::vector<Graphics::AttachmentInfo>& attachments, std::vector<Graphics::SubPassDependency>& dependencies) {
    create_hair_scattering_images();
}

void HairScatteringPass::setup_uniforms(std::vector<Graphics::Frame>& frames) {
    m_descriptorPool = m_device->create_descriptor_pool(ENGINE_MAX_OBJECTS, ENGINE_MAX_OBJECTS, ENGINE_MAX_OBJECTS, ENGINE_MAX_OBJECTS, ENGINE_MAX_OBJECTS);
    m_descriptors.resize(frames.size());

    // GLOBAL SET
    LayoutBinding backImgBinding(UNIFORM_STORAGE_IMAGE, SHADER_STAGE_COMPUTE, 0);
    LayoutBinding frontImgBinding(UNIFORM_STORAGE_IMAGE, SHADER_STAGE_COMPUTE, 1);
    LayoutBinding distributionBinding(UNIFORM_COMBINED_IMAGE_SAMPLER, SHADER_STAGE_COMPUTE, 2);
    m_descriptorPool.set_layout(GLOBAL_LAYOUT, {backImgBinding, frontImgBinding, distributionBinding});
    // PER-OBJECT SET
    LayoutBinding objectBufferBinding(UNIFORM_DYNAMIC_BUFFER, SHADER_STAGE_COMPUTE, 0);
    LayoutBinding materialBufferBinding(UNIFORM_DYNAMIC_BUFFER, SHADER_STAGE_COMPUTE, 1);
    m_descriptorPool.set_layout(OBJECT_LAYOUT, {objectBufferBinding, materialBufferBinding});

    for (size_t i = 0; i < frames.size(); i++)
    {

        m_descriptorPool.allocate_descriptor_set(GLOBAL_LAYOUT, &m_descriptors[i].globalDescritor);
        m_descriptorPool.set_descriptor_write(&m_backAtt, LAYOUT_GENERAL, &m_descriptors[i].globalDescritor, 0, UNIFORM_STORAGE_IMAGE);
        m_descriptorPool.set_descriptor_write(&m_frontAtt, LAYOUT_GENERAL, &m_descriptors[i].globalDescritor, 1, UNIFORM_STORAGE_IMAGE);
        m_descriptorPool.set_descriptor_write(
            get_image(ResourceManager::HAIR_IRRADIANCE_DISTRIBUTION_TEXTURE), LAYOUT_SHADER_READ_ONLY_OPTIMAL, &m_descriptors[i].globalDescritor, 2);

        // Per-object
        m_descriptorPool.allocate_descriptor_set(OBJECT_LAYOUT, &m_descriptors[i].objectDescritor);
        m_descriptorPool.set_descriptor_write(
            &frames[i].uniformBuffers[OBJECT_LAYOUT], sizeof(ObjectUniforms), 0, &m_descriptors[i].objectDescritor, UNIFORM_DYNAMIC_BUFFER, 0);
        m_descriptorPool.set_descriptor_write(&frames[i].uniformBuffers[OBJECT_LAYOUT],
                                              sizeof(MaterialUniforms),
                                              m_device->pad_uniform_buffer_size(sizeof(MaterialUniforms)),
                                              &m_descriptors[i].objectDescritor,
                                              UNIFORM_DYNAMIC_BUFFER,
                                              1);
    }
}

void HairScatteringPass::setup_shader_passes() {

    ComputeShaderPass* mergePass = new ComputeShaderPass(m_device->get_handle(), ENGINE_RESOURCES_PATH "shaders/misc/compute_hair_fiber_scattering.glsl");
    mergePass->settings.descriptorSetLayoutIDs = {{GLOBAL_LAYOUT, true}, {OBJECT_LAYOUT, true}, {OBJECT_TEXTURE_LAYOUT, false}};

    mergePass->build_shader_stages();
    mergePass->build(m_descriptorPool);

    m_shaderPasses[0] = mergePass;
}

void HairScatteringPass::render(Graphics::Frame& currentFrame, Scene* const scene, uint32_t presentImageIndex) {

    PROFILING_EVENT()

    CommandBuffer cmd = currentFrame.commandBuffer;

    /*
    PREPARE IMAGE TO BE USED IN SHADERS
    */
    if (m_backAtt.currentLayout == LAYOUT_UNDEFINED)
    {
        cmd.pipeline_barrier(m_backAtt, LAYOUT_UNDEFINED, LAYOUT_GENERAL, ACCESS_NONE, ACCESS_SHADER_WRITE, STAGE_TOP_OF_PIPE, STAGE_COMPUTE_SHADER);
        cmd.pipeline_barrier(m_frontAtt, LAYOUT_UNDEFINED, LAYOUT_GENERAL, ACCESS_NONE, ACCESS_SHADER_WRITE, STAGE_TOP_OF_PIPE, STAGE_COMPUTE_SHADER);
    }

    /*
 PREPARE FOR SHADER WRITE
  */
    if (m_backAtt.currentLayout == LAYOUT_SHADER_READ_ONLY_OPTIMAL)
    {
        cmd.pipeline_barrier(
            m_backAtt, LAYOUT_SHADER_READ_ONLY_OPTIMAL, LAYOUT_GENERAL, ACCESS_SHADER_READ, ACCESS_SHADER_WRITE, STAGE_FRAGMENT_SHADER, STAGE_COMPUTE_SHADER);
        cmd.pipeline_barrier(
            m_frontAtt, LAYOUT_SHADER_READ_ONLY_OPTIMAL, LAYOUT_GENERAL, ACCESS_SHADER_READ, ACCESS_SHADER_WRITE, STAGE_FRAGMENT_SHADER, STAGE_COMPUTE_SHADER);
    }

    ShaderPass* shaderPass = m_shaderPasses[0];
    // Bind pipeline
    cmd.bind_shaderpass(*shaderPass);
    // GLOBAL LAYOUT BINDING
    cmd.bind_descriptor_set(m_descriptors[currentFrame.index].globalDescritor, 0, *shaderPass, {}, BINDING_TYPE_COMPUTE);

    unsigned int mesh_idx = 0;
    for (Mesh* m : scene->get_meshes())
    {
        if (m)
        {
            if (m->is_active() &&  // Check if is active
                m->get_geometry()) // Check if is inside frustrum
            {
                auto mat = m->get_material();
                if (mat->get_type() == Core::IMaterial::Type::HAIR_STR_TYPE)
                {

                    // Offset calculation
                    uint32_t objectOffset = currentFrame.uniformBuffers[1].strideSize * mesh_idx;

                    // PER OBJECT LAYOUT BINDING
                    cmd.bind_descriptor_set(
                        m_descriptors[currentFrame.index].objectDescritor, 1, *shaderPass, {objectOffset, objectOffset}, BINDING_TYPE_COMPUTE);

                    // Dispatch the compute shader
                    const uint32_t WORK_GROUP_SIZE = 16;
                    uint32_t       gridSize        = std::max(1u, m_imageExtent.width);
                    gridSize                       = (gridSize + WORK_GROUP_SIZE - 1) / WORK_GROUP_SIZE;
                    cmd.dispatch_compute({gridSize, 1, 1});

                    break; // WIP for now compute just one hair volume AND EXIT LOOP
                }
            }
        }
        mesh_idx++;
    }

    /*
      PREPARE FOR SHADER READ
       */
    cmd.pipeline_barrier(
        m_backAtt, LAYOUT_GENERAL, LAYOUT_SHADER_READ_ONLY_OPTIMAL, ACCESS_SHADER_WRITE, ACCESS_SHADER_READ, STAGE_COMPUTE_SHADER, STAGE_FRAGMENT_SHADER);
    cmd.pipeline_barrier(
        m_frontAtt, LAYOUT_GENERAL, LAYOUT_SHADER_READ_ONLY_OPTIMAL, ACCESS_SHADER_WRITE, ACCESS_SHADER_READ, STAGE_COMPUTE_SHADER, STAGE_FRAGMENT_SHADER);
}

void HairScatteringPass::cleanup() {
    ComputePass::cleanup();
    m_backAtt.cleanup();
    m_frontAtt.cleanup();
}

} // namespace Core

VULKAN_ENGINE_NAMESPACE_END