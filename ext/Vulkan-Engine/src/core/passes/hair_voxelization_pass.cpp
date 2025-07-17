#include <engine/core/passes/hair_voxelization_pass.h>

VULKAN_ENGINE_NAMESPACE_BEGIN
using namespace Graphics;
namespace Core {

void HairVoxelizationPass::create_voxelization_image() {

    // Actual Voxel Image
    ResourceManager::HAIR_DENSITY_VOLUME.cleanup();

    ImageConfig config                   = {};
    config.viewType                      = TEXTURE_3D;
    config.format                        = R_32_UINT;
    config.usageFlags                    = IMAGE_USAGE_SAMPLED | IMAGE_USAGE_TRANSFER_DST | IMAGE_USAGE_TRANSFER_SRC | IMAGE_USAGE_STORAGE;
    config.mipLevels                     = 1;
    ResourceManager::HAIR_DENSITY_VOLUME = m_device->create_image({m_imageExtent.width, m_imageExtent.width, m_imageExtent.width}, config, false);
    ResourceManager::HAIR_DENSITY_VOLUME.create_view(config);

    SamplerConfig samplerConfig      = {};
    samplerConfig.samplerAddressMode = ADDRESS_MODE_CLAMP_TO_BORDER;
    samplerConfig.border             = BorderColor::FLOAT_OPAQUE_BLACK;
    ResourceManager::HAIR_DENSITY_VOLUME.create_sampler(samplerConfig);

    // Codified percieved Density
    ResourceManager::HAIR_PERECEIVED_DENSITY_VOLUME.cleanup();

    ImageConfig config                   = {};
    config.viewType                      = TEXTURE_3D;
    config.format                        = R_32_UINT;
    config.usageFlags                    = IMAGE_USAGE_SAMPLED | IMAGE_USAGE_TRANSFER_DST | IMAGE_USAGE_TRANSFER_SRC | IMAGE_USAGE_STORAGE;
    config.mipLevels                     = 1;
    ResourceManager::HAIR_PERECEIVED_DENSITY_VOLUME = m_device->create_image({m_imageExtent.width, m_imageExtent.width, m_imageExtent.width}, config, false);
    ResourceManager::HAIR_PERECEIVED_DENSITY_VOLUME.create_view(config);

    SamplerConfig samplerConfig      = {};
    samplerConfig.samplerAddressMode = ADDRESS_MODE_CLAMP_TO_BORDER;
    samplerConfig.border             = BorderColor::FLOAT_OPAQUE_BLACK;
    ResourceManager::HAIR_PERECEIVED_DENSITY_VOLUME.create_sampler(samplerConfig);
}

void HairVoxelizationPass::setup_attachments(std::vector<Graphics::AttachmentInfo>& attachments, std::vector<Graphics::SubPassDependency>& dependencies) {

    attachments.resize(1);

    attachments[0] = Graphics::AttachmentInfo(R_8U,
                                              1,
                                              LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                                              LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                                              IMAGE_USAGE_COLOR_ATTACHMENT | IMAGE_USAGE_SAMPLED,
                                              COLOR_ATTACHMENT,
                                              ASPECT_COLOR);
    create_voxelization_image();
    // Depdencies
    dependencies.resize(2);

    dependencies[0]               = Graphics::SubPassDependency(STAGE_BOTTOM_OF_PIPE, STAGE_COLOR_ATTACHMENT_OUTPUT, ACCESS_COLOR_ATTACHMENT_WRITE);
    dependencies[0].srcAccessMask = ACCESS_MEMORY_READ;
    dependencies[1]               = Graphics::SubPassDependency(STAGE_COLOR_ATTACHMENT_OUTPUT, STAGE_BOTTOM_OF_PIPE, ACCESS_MEMORY_READ);
    dependencies[1].srcAccessMask = ACCESS_COLOR_ATTACHMENT_WRITE;
    dependencies[1].srcSubpass    = 0;
    dependencies[1].dstSubpass    = VK_SUBPASS_EXTERNAL;

    m_isResizeable = false;
}
void HairVoxelizationPass::setup_uniforms(std::vector<Graphics::Frame>& frames) {

    m_descriptorPool = m_device->create_descriptor_pool(ENGINE_MAX_OBJECTS, ENGINE_MAX_OBJECTS, ENGINE_MAX_OBJECTS, ENGINE_MAX_OBJECTS, ENGINE_MAX_OBJECTS);
    m_descriptors.resize(frames.size());

    // GLOBAL SET
    LayoutBinding camBufferBinding(UNIFORM_DYNAMIC_BUFFER, SHADER_STAGE_VERTEX | SHADER_STAGE_GEOMETRY | SHADER_STAGE_FRAGMENT, 0);
    LayoutBinding sceneBufferBinding(UNIFORM_DYNAMIC_BUFFER, SHADER_STAGE_VERTEX | SHADER_STAGE_GEOMETRY | SHADER_STAGE_FRAGMENT, 1);
    LayoutBinding voxelBinding(UNIFORM_STORAGE_IMAGE, SHADER_STAGE_FRAGMENT, 2);
    m_descriptorPool.set_layout(GLOBAL_LAYOUT, {camBufferBinding, sceneBufferBinding, voxelBinding});

    // PER-OBJECT SET
    LayoutBinding objectBufferBinding(UNIFORM_DYNAMIC_BUFFER, SHADER_STAGE_VERTEX | SHADER_STAGE_GEOMETRY | SHADER_STAGE_FRAGMENT, 0);
    LayoutBinding materialBufferBinding(UNIFORM_DYNAMIC_BUFFER, SHADER_STAGE_VERTEX | SHADER_STAGE_GEOMETRY | SHADER_STAGE_FRAGMENT, 1);
    m_descriptorPool.set_layout(OBJECT_LAYOUT, {objectBufferBinding, materialBufferBinding});

    for (size_t i = 0; i < frames.size(); i++)
    {
        // Global
        m_descriptorPool.allocate_descriptor_set(GLOBAL_LAYOUT, &m_descriptors[i].globalDescritor);
        m_descriptorPool.set_descriptor_write(
            &frames[i].uniformBuffers[GLOBAL_LAYOUT], sizeof(CameraUniforms), 0, &m_descriptors[i].globalDescritor, UNIFORM_DYNAMIC_BUFFER, 0);
        m_descriptorPool.set_descriptor_write(&frames[i].uniformBuffers[GLOBAL_LAYOUT],
                                              sizeof(SceneUniforms),
                                              m_device->pad_uniform_buffer_size(sizeof(CameraUniforms)),
                                              &m_descriptors[i].globalDescritor,
                                              UNIFORM_DYNAMIC_BUFFER,
                                              1);
        // Voxelization Image
        m_descriptorPool.set_descriptor_write(
            &ResourceManager::HAIR_DENSITY_VOLUME, LAYOUT_GENERAL, &m_descriptors[i].globalDescritor, 2, UNIFORM_STORAGE_IMAGE);

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
void HairVoxelizationPass::setup_shader_passes() {

    GraphicShaderPass* voxelPass =
        new GraphicShaderPass(m_device->get_handle(), m_renderpass, m_imageExtent, ENGINE_RESOURCES_PATH "shaders/misc/density_voxelization.glsl");
    voxelPass->settings.descriptorSetLayoutIDs = {{GLOBAL_LAYOUT, true}, {OBJECT_LAYOUT, true}, {OBJECT_TEXTURE_LAYOUT, false}};
    voxelPass->graphicSettings.attributes      = {
        {POSITION_ATTRIBUTE, true}, {NORMAL_ATTRIBUTE, false}, {UV_ATTRIBUTE, false}, {TANGENT_ATTRIBUTE, false}, {COLOR_ATTRIBUTE, false}};
    voxelPass->graphicSettings.dynamicStates    = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineColorBlendAttachmentState state   = Init::color_blend_attachment_state(false);
    state.colorWriteMask                        = 0;
    voxelPass->graphicSettings.depthTest        = false;
    voxelPass->graphicSettings.blendAttachments = {state};
    voxelPass->graphicSettings.topology         = VK_PRIMITIVE_TOPOLOGY_LINE_LIST;

    voxelPass->build_shader_stages();
    voxelPass->build(m_descriptorPool);

    m_shaderPasses[0] = voxelPass;

    // ComputeShaderPass* mergePass               = new ComputeShaderPass(m_device->get_handle(), GET_RESOURCE_PATH("shaders/VXGI/merge_intermediates.glsl"));
    // mergePass->settings.descriptorSetLayoutIDs = {{GLOBAL_LAYOUT, true}, {OBJECT_LAYOUT, false}, {OBJECT_TEXTURE_LAYOUT, false}};

    // mergePass->build_shader_stages();
    // mergePass->build(m_descriptorPool);

    // m_shaderPasses["merge"] = mergePass;
}
void HairVoxelizationPass::render(Graphics::Frame& currentFrame, Scene* const scene, uint32_t presentImageIndex) {
    PROFILING_EVENT()

    CommandBuffer cmd = currentFrame.commandBuffer;

    /*
    PREPARE VOXEL IMAGES TO BE USED IN SHADERS
    */
    if (ResourceManager::HAIR_DENSITY_VOLUME.currentLayout == LAYOUT_UNDEFINED)
    {
        cmd.pipeline_barrier(
            ResourceManager::HAIR_DENSITY_VOLUME, LAYOUT_UNDEFINED, LAYOUT_GENERAL, ACCESS_NONE, ACCESS_SHADER_READ, STAGE_TOP_OF_PIPE, STAGE_FRAGMENT_SHADER);
    }
    /*
    CLEAR IMAGES
    */
    cmd.clear_image(ResourceManager::HAIR_DENSITY_VOLUME, LAYOUT_GENERAL, ASPECT_COLOR, Vec4(0.0));
    /*
    POPULATE AUXILIAR IMAGES WITH DENSITY
    */
    cmd.begin_renderpass(m_renderpass, m_framebuffers[0]);

    cmd.set_viewport(m_imageExtent);

    if (scene->get_active_camera() && scene->get_active_camera()->is_active())
    {

        ShaderPass* shaderPass = m_shaderPasses[0];
        // Bind pipeline
        cmd.bind_shaderpass(*shaderPass);
        // GLOBAL LAYOUT BINDING
        cmd.bind_descriptor_set(m_descriptors[currentFrame.index].globalDescritor, 0, *shaderPass, {0, 0});

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

                        // PER OBJECT LAYOUT BINDING
                        uint32_t objectOffset = currentFrame.uniformBuffers[1].strideSize * mesh_idx;
                        cmd.bind_descriptor_set(m_descriptors[currentFrame.index].objectDescritor, 1, *shaderPass, {objectOffset, objectOffset});

                        // DRAW
                        auto g = m->get_geometry();
                        cmd.draw_geometry(*get_VAO(g));

                        break;
                    }
                }
            }
            mesh_idx++;
        }
    }

    cmd.end_renderpass(m_renderpass, m_framebuffers[0]);

    /*
    GENERATE MIPMAPS FOR UPPER DENSITY LEVELS
    */
    // cmd.pipeline_barrier(ResourceManager::HAIR_DENSITY_VOLUME,
    //                      LAYOUT_GENERAL,
    //                      LAYOUT_TRANSFER_DST_OPTIMAL,
    //                      ACCESS_SHADER_WRITE,
    //                      ACCESS_TRANSFER_READ,
    //                      STAGE_COMPUTE_SHADER,
    //                      STAGE_TRANSFER);

    // cmd.generate_mipmaps(ResourceManager::HAIR_DENSITY_VOLUME, LAYOUT_TRANSFER_DST_OPTIMAL, LAYOUT_GENERAL, FILTER_NEAREST);

    /*
    DISPATCH COMPUTE FOR POPULATING FINAL PERCEIVED DENSITY IMAGE
    */

    // ShaderPass* mergePass = m_shaderPasses["merge"];
    // cmd.bind_shaderpass(*mergePass);

    // cmd.bind_descriptor_set(m_descriptors[currentFrame.index].globalDescritor, 0, *mergePass, {0, 0}, BINDING_TYPE_COMPUTE);

    // // Dispatch the compute shader
    // const uint32_t WORK_GROUP_SIZE = 4;
    // uint32_t       gridSize        = std::max(1u, m_imageExtent.width);
    // gridSize                       = (gridSize + WORK_GROUP_SIZE - 1) / WORK_GROUP_SIZE;
    // cmd.dispatch_compute({gridSize, gridSize, gridSize});
}

// void HairVoxelizationPass::resize_attachments() {
//     for (Graphics::Framebuffer& fb : m_framebuffers)
//         fb.cleanup();
//     for (Graphics::Image* img : m_outAttachments)
//         img->cleanup();
//     for (Graphics::Image& img : m_interAttachments)
//         img.cleanup();
//     create_voxelization_image();
//     create_framebuffer();

//     for (size_t i = 0; i < m_descriptors.size(); i++)
//     {
//         // Voxelization Image
//         m_descriptors[i].globalDescritor.update(m_outAttachments[0], LAYOUT_GENERAL, 6, UNIFORM_STORAGE_IMAGE);
// #ifdef USE_IMG_ATOMIC_OPERATION
//         // Voxelization Aux.Images
//         std::vector<Graphics::Image> auxImages = {m_interAttachments[0], m_interAttachments[1], m_interAttachments[2]};
//         m_descriptors[i].globalDescritor.update(auxImages, LAYOUT_GENERAL, 7, UNIFORM_STORAGE_IMAGE);
//         m_descriptors[i].globalDescritor.update(auxImages, LAYOUT_GENERAL, 8);
// #endif
//     }
// }

void HairVoxelizationPass::cleanup() {
    ResourceManager::HAIR_DENSITY_VOLUME.cleanup();
    GraphicPass::cleanup();
}
} // namespace Core

VULKAN_ENGINE_NAMESPACE_END
