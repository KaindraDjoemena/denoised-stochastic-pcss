// main.cpp

#include <bolero.hpp>

#include "passes/opaque.hpp"  // light pass
#include "passes/dir_shadow.hpp"  // shadow pass
#include "passes/spot_shadow.hpp"
#include "passes/point_shadow.hpp"
#include "passes/ibl_setup.hpp"
#include "passes/irradiance.hpp"
#include "passes/prefilter.hpp"
#include "passes/brdf_lut.hpp"
#include "passes/post.hpp"

#include "deferred_passes/geometry_pass.hpp"
#include "deferred_passes/shadow_mask_pass.hpp"
#include "deferred_passes/denoiser_pass.hpp"
#include "deferred_passes/lighting_pass.hpp"
#include "deferred_passes/ui.hpp"

#include <iostream>

namespace blrc = blr::core;
namespace blra = blr::app;

// Force GPU usage
#ifdef _WIN32
    extern "C"
    {
        __declspec(dllexport) uint32_t NvOptimusEnablement = 1;
        
        __declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
    }
#endif

constexpr int         DEFAULT_WINDOW_WIDTH  = 1280;
constexpr int         DEFAULT_WINDOW_HEIGHT = 720;
constexpr const char* DEFAULT_WINDOW_TITLE  = "Bolero: Renderer";

float deltaTime = 0.0f;	
float lastFrame = 0.0f;


int main()
{
#ifdef BOLERO_DEV_ASSET_DIR
    blrc::VFS::Mount("bolero://", BOLERO_DEV_ASSET_DIR);
#endif

    blrc::VFS::Mount("app://", "../src/");

    blra::Input input;
    blra::Window window(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, DEFAULT_WINDOW_TITLE, input);
    window.AddResizeCallback([](uint32_t w, uint32_t h) {
            glViewport(0, 0, w, h);
        });
    
    blr::utils::PrintSystemInfo();

    blrc::Camera cam;
    cam.SetYaw(blrc::DegToRad(100.0f));
    cam.SetPitch(blrc::DegToRad(-7.0f));
    cam.SetDistance(9.15f);
    cam.SetTarget(blrc::vec3(0.0f, 1.9f, 0.9f));


    cam.SetAspect((float)window.GetWidth() / (float)window.GetHeight());
    window.AddResizeCallback([&cam](uint32_t w, uint32_t h) {
            // For minimized windows
            if (w == 0 || h == 0)
                return;

            cam.SetAspect((float)w / (float)h);
        });
    input.AddMouseScrollCallback([&cam](double xOffset, double yOffset) {
            cam.OnScroll(yOffset);
        });
    input.AddMouseButtonCallback([&input, &cam](int button, int action, int mods) {
                if (button == blra::Input::MOUSE_BUTTON_MIDDLE)
                {
                    if (action == blra::Input::ACTION_PRESS)
                    {
                        cam.BeginDrag(glm::vec2(input.GetMouseX(), input.GetMouseY()), input.IsKeyDown(blra::Input::KEY_L_SHIFT));
                    }
                    else if (action == blra::Input::ACTION_RELEASE)
                    {
                        cam.EndDrag();
                    }
                }
            });

    
    blrc::Renderer::Init();
    blrc::AssetManager assetManager;
    blrc::Scene        scene;
    scene.SetCam(&cam);
    
    // Model
    auto gShader = assetManager.CreateShader("app://deferred_passes/geometry_pass.glsl");
    auto model = assetManager.CreateModel("bolero://models/squares_and_things.gltf", gShader);
    blrc::Transform transform;
    scene.AddEntity(model, transform);

    // Light
    blrc::PointLight pointLight;
    pointLight.base.power  = 0.0f;
    pointLight.castsShadow = false;
    scene.AddLight(pointLight);

    blrc::SpotLight spotLight;
    spotLight.castsShadow = false;
    spotLight.base.power  = 0.0f;
    scene.AddLight(spotLight);

    blrc::DirLight dirLight;
    dirLight.direction   = blrc::vec3(-0.18f, -1.0f, 0.0f);
    dirLight.shadowFar   = 40.0f;
    dirLight.castsShadow = true;
    dirLight.base.power  = 100.0f;
    scene.AddLight(dirLight);

    blrc::RenderPipeline deferredRenderer;

    window.AddResizeCallback([&deferredRenderer](uint32_t w, uint32_t h) {
            deferredRenderer
    .OnResize(w, h);
        });


    // Render pass context
    blrc::RenderContext renderCtx;

    // IBL Skybox Setup Pass
    auto hdrMap = assetManager.CreateTex("bolero://hdri/citrus_orchard_puresky_2k.hdr");
    auto eqToCubeShader = assetManager.CreateShader("bolero://shaders/equirect_to_cubemap.glsl");
    blrc::Ref<IBLSetupPass> iblPass = std::make_shared<IBLSetupPass>(eqToCubeShader, hdrMap);
    // Scene Irradiance Pass
    auto convolutionShader = assetManager.CreateShader("bolero://shaders/cubemap_convolution.glsl");
    blrc::Ref<IrradiancePass> irradiancePass = std::make_shared<IrradiancePass>(convolutionShader);
    // Environment Map Prefiltering Pass
    auto prefilterShader = assetManager.CreateShader("bolero://shaders/prefilter.glsl");
    blrc::Ref<PrefilterPass> prefilterPass = std::make_shared<PrefilterPass>(prefilterShader);
    // BRDF LUT Pre Computation
    auto brdfLutShader = assetManager.CreateShader("bolero://shaders/brdf_lut.glsl");
    blrc::Ref<BrdfLutPass> brdfLutPass = std::make_shared<BrdfLutPass>(assetManager, brdfLutShader);

    // Geometry Pass
    blrc::Ref<GPass> gPass = std::make_shared<GPass>(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, gShader);
    
    // Shadow Mask Pass
    auto shadowMaskShader = assetManager.CreateShader("app://deferred_passes/shadow_mask_pass.glsl");
    blrc::Ref<ShadowMaskPass> shadowMaskPass = std::make_shared<ShadowMaskPass>(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, shadowMaskShader);

    // Denoised Pass
    auto denoiserShader = assetManager.CreateShader("app://deferred_passes/denoiser_pass.glsl");
    blrc::Ref<DenoiserPass> denoiserPass = std::make_shared<DenoiserPass>(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, denoiserShader);

    // Scene Depth Pass (Shadow Mapping)
    auto depthShader      = assetManager.CreateShader("bolero://shaders/shadow_pass.glsl");
    auto pointDepthShader = assetManager.CreateShader("bolero://shaders/point_shadow_pass.glsl");
    blrc::Ref<DirShadowPass>   dirShadowPass   = std::make_shared<DirShadowPass>(depthShader);
    blrc::Ref<SpotShadowPass>  spotShadowPass  = std::make_shared<SpotShadowPass>(depthShader);
    blrc::Ref<PointShadowPass> pointShadowPass = std::make_shared<PointShadowPass>(pointDepthShader);

    // Lighting Pass
    auto lShader = assetManager.CreateShader("app://deferred_passes/lighting_pass.glsl");
    auto skyboxShader = assetManager.CreateShader("bolero://shaders/skybox.glsl");
    blrc::Ref<LightingPass> lPass = std::make_shared<LightingPass>(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, lShader, skyboxShader);

    // Post Process Pass
    auto postShader = assetManager.CreateShader("bolero://shaders/post_pass.glsl");
    blrc::Ref<PostPass> postPass = std::make_shared<PostPass>(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, postShader);
    // UI Pass
    blrc::Ref<UIPass> uiPass = std::make_shared<UIPass>(window.GetNativeWindow(), deferredRenderer.GetPasses());

    // Add Passes to the pipeline
    deferredRenderer.AddPass(iblPass);
    deferredRenderer.AddPass(irradiancePass);
    deferredRenderer.AddPass(prefilterPass);
    deferredRenderer.AddPass(brdfLutPass);
    deferredRenderer.AddPass(dirShadowPass);
    deferredRenderer.AddPass(spotShadowPass);
    deferredRenderer.AddPass(pointShadowPass);
    deferredRenderer.AddPass(gPass);
    deferredRenderer.AddPass(shadowMaskPass);
    deferredRenderer.AddPass(denoiserPass);
    deferredRenderer.AddPass(lPass);
    deferredRenderer.AddPass(postPass);
    deferredRenderer.AddPass(uiPass);


    float hotReloadTimer = 0.0;
    while (!window.ShouldClose())
    {
        float currentFrame = static_cast<float>(glfwGetTime());
        deltaTime = currentFrame - lastFrame;
        lastFrame = currentFrame;

        // Animate Light
        // auto& sceneDirLight = scene.GetDirLights()[0];
        // sceneDirLight.direction.z = std::sin(currentFrame / 10.0f);

        hotReloadTimer += deltaTime;
        if (hotReloadTimer > 1.0f)
        {
            assetManager.Update();
            hotReloadTimer = 0.0f;
        }

        window.PollEvents();

        // Skip frame when the window is minimized
        if (window.GetHeight() == 0 || window.GetWidth() == 0)
            continue;

        cam.HandleDrag(glm::vec2(input.GetMouseX(), input.GetMouseY()));

        blrc::Renderer::BeginFrame();
        
        scene.Update(deltaTime, true);

        renderCtx.ClearTransient();
        deferredRenderer.Execute(scene, renderCtx);  // pass scene

        window.SwapBuffers();
    }

    blrc::Renderer::Shutdown();

    return 0;
}
