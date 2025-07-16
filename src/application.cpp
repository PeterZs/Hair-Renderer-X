#include "application.h"
#include <filesystem>

// #define USE_NEURAL_MODELS

void HairViewer::init(Systems::RendererSettings settings) {
    m_window = new WindowGLFW("Hair Viewer", 1024, 1024);

    m_window->init();
    m_window->set_window_icon(RESOURCES_PATH "textures/icon.png");

    m_window->set_window_size_callback(
        std::bind(&HairViewer::window_resize_callback, this, std::placeholders::_1, std::placeholders::_2));
    m_window->set_mouse_callback(
        std::bind(&HairViewer::mouse_callback, this, std::placeholders::_1, std::placeholders::_2));
    m_window->set_key_callback(std::bind(&HairViewer::keyboard_callback,
                                         this,
                                         std::placeholders::_1,
                                         std::placeholders::_2,
                                         std::placeholders::_3,
                                         std::placeholders::_4));

    m_renderer = new Systems::ForwardRenderer(m_window, ShadowResolution::HIGH, settings);

    setup();

    m_interface.init(m_window, m_scene, m_renderer);
    // m_renderer->set_gui_overlay(m_interface.overlay);
}

void HairViewer::run(Systems::RendererSettings settings) {

    init(settings);
    while (!m_window->get_window_should_close())
    {

        // I-O
        m_window->poll_events();

        tick();
    }
    m_renderer->shutdown(m_scene);
}

void HairViewer::setup() {
    const std::string MESH_PATH(RESOURCES_PATH "models/");
    const std::string TEXTURE_PATH(RESOURCES_PATH "textures/");
    const std::string ENGINE_MESH_PATH(ENGINE_RESOURCES_PATH "meshes/");

    camera = new Camera();
    camera->set_position(Vec3(0.0f, 0.0f, -16.0f));
    camera->set_far(100.0f);
    camera->set_near(0.1f);
    camera->set_field_of_view(40.0f);

    m_scene = new Scene(camera);

    PointLight* light = new PointLight();
    light->set_position({-1.3f, 8.0f, -5.8f});
    light->set_shadow_fov(120.0f);
    light->set_intensity(1.0f);
    light->set_shadow_bias(0.0002f);
    light->set_shadow_near(0.1f);
    light->set_area_of_effect(30.0f);
    light->set_name("PointLight");

    Mesh* lightDummy = new Mesh();
    Tools::Loaders::load_3D_file(lightDummy, ENGINE_MESH_PATH + "sphere.obj", false);
    lightDummy->push_material(new UnlitMaterial());
    lightDummy->cast_shadows(false);
    lightDummy->set_name("LightDummy");
    light->add_child(lightDummy);

    m_scene->add(light);

#ifdef USE_NEURAL_MODELS
    // load_neural_avatar(RESOURCES_PATH "models/neural_hair_PABLO.ply",
    //                    RESOURCES_PATH "models/neural_head_PABLO.ply",
    //                    "Pablo",
    //                    {1, 1, 1},
    //                    Vec3(0.0),
    //                    -175.0f);
    // load_neural_avatar(RESOURCES_PATH "models/neural_hair_ALVARO.ply",
    //                    RESOURCES_PATH "models/neural_head_ALVARO.ply",
    //                    "Alvaro",
    //                    {9, 6, 4},
    //                    {-5.5f, 0.1f, -0.4f},
    //                    -35.0f);
    load_neural_avatar(RESOURCES_PATH "models/neural_hair_TONO.ply",
                       RESOURCES_PATH "models/neural_head_TONO.ply",
                       "Antonio",
                       {24, 4, 24},
                       //    {5.5f, 0.0f, 0.0f},
                       {0.0f, 0.0f, 0.0f},
                       -320.0f);
    //    {9, 6, 3}
#else
    Mesh* hair = new Mesh();
    Tools::Loaders::load_3D_file(hair, MESH_PATH + "straight.hair", false);
    hair->set_scale(0.053f);
    hair->set_rotation({90.0, 180.0f, 0.0f});
    HairMaterial* hmat = new HairMaterial(0.4);
    hmat->set_thickness(0.0025f);
    hair->push_material(hmat);
    hair->set_name("Hair");

    Mesh* head = new Mesh();
    Tools::Loaders::load_3D_file(head, MESH_PATH + "woman2.ply");
    head->set_rotation({0.0, 225.0f, 180.0f});
    auto     headMat    = new PhysicallyBasedMaterial();
    Texture* headAlbedo = new Texture();
    Tools::Loaders::load_texture(headAlbedo, TEXTURE_PATH + "head.png");
    headMat->set_albedo_texture(headAlbedo);
    headMat->set_albedo(Vec3(204.0f, 123.0f, 85.0f)  / 255.0f);
    headMat->set_albedo_weight(0.75f);
    headMat->set_metalness(0.0f);
    headMat->set_roughness(0.5f);
    head->push_material(headMat);
    head->set_name("Head");
    Mesh* eyes = new Mesh();
    Tools::Loaders::load_3D_file(eyes, MESH_PATH + "eyes.ply");
    auto     eyesMat    = new PhysicallyBasedMaterial();
    eyes->push_material(eyesMat);
    Texture* eyesAlbedo = new Texture();
    Tools::Loaders::load_texture(eyesAlbedo, TEXTURE_PATH + "eye.png");
    eyesMat->set_albedo_texture(eyesAlbedo);
    eyesMat->set_metalness(0.0f);
    eyesMat->set_roughness(0.1f);
    eyes->set_name("Eyes");
    head->add_child(eyes);
    // head->add_child(hair);
    m_scene->add(hair);
    // m_scene->add(head);
#endif

    m_scene->set_ambient_color({0.05, 0.05, 0.05});
    m_scene->set_ambient_intensity(0.05f);

    TextureHDR* envMap = new TextureHDR();
    Tools::Loaders::load_HDRi(envMap, TEXTURE_PATH + "room.hdr");
    Skybox* sky = new Skybox(envMap);
    sky->set_color_intensity(0.1);
    m_scene->set_skybox(sky);
    m_scene->set_use_IBL(false);

    m_scene->enable_fog(false);

    m_controller = new Tools::Controller(camera, m_window, ControllerMovementType::ORBITAL);
}

void HairViewer::update() {
    if (!m_interface.overlay->wants_to_handle_input())
        m_controller->handle_keyboard(0, 0, m_time.delta);

    // Rotate the vector around the ZX plane
    auto light = m_scene->get_lights()[0];
    if (animateLight)
    {
        float rotationAngle = glm::radians(10.0f * m_time.delta);
        float _x = light->get_position().x * cos(rotationAngle) - light->get_position().z * sin(rotationAngle);
        float _z = light->get_position().x * sin(rotationAngle) + light->get_position().z * cos(rotationAngle);

        light->set_position({_x, light->get_position().y, _z});
        static_cast<UnlitMaterial*>(static_cast<Mesh*>(light->get_children().front())->get_material(0))
            ->set_color({light->get_color()*4.0f, 1.0f});
    }

    m_interface.objectWidget->set_object(m_interface.sceneWidget->get_selected_object());
}

void HairViewer::tick() {
    float currentTime      = (float)m_window->get_time_elapsed();
    m_time.delta           = currentTime - m_time.last;
    m_time.last            = currentTime;
    m_time.framesPerSecond = 1.0f / m_time.delta;

    update();

    m_interface.overlay->render();
    m_renderer->render(m_scene);
}
void HairViewer::load_neural_avatar(const char* hairFile,
                                    const char* headFile,
                                    const char* objName,
                                    math::ivec3 hairColor,
                                    Vec3        position,
                                    float       rotation) {

    Mesh*       hair = new Mesh();
    std::thread loadThread1(hair_loaders::load_neural_hair, hair, hairFile, nullptr, true, false, false, false);
    loadThread1.detach();

    HairMaterial* hmat = new HairMaterial();
    hair->push_material(hmat);
    hair->set_name(std::string(objName) + " hair");

    const std::string HEAD_PATH(headFile);
    Mesh*             head = new Mesh();
    Tools::Loaders::load_3D_file(head, HEAD_PATH);

    // Transform
    head->set_position(position);
    head->set_scale(3.f);
    head->set_rotation({-90.0, 0.0f, 215.0f + rotation}); // Correct blender axis

    auto headMat = new PhysicallyBasedMaterial();
    headMat->set_albedo(Vec3(204.0f, 123.0f, 85.0f) / 255.0f);
    headMat->set_metalness(0.0f);
    headMat->set_roughness(0.55f);
    head->push_material(headMat);
    head->set_name(std::string(objName) + " head");

    head->add_child(hair);
    m_scene->add(head);
}
