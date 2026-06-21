// geometry_pass.hpp

#pragma once

#include <bolero.hpp>

namespace blrc = blr::core;

class GPass : public blrc::RenderPass
{
public:
    GPass(uint32_t initW, uint32_t initH, const blrc::Ref<blrc::Shader>& gShader)
    : RenderPass("Geometry Pass")
    , m_initW(initW)
    , m_initH(initH)
    , m_gShader(gShader)
    {
    }

    void Init() override
    {
        m_fbo = blrc::FrameBuffer::Create({ m_initW, m_initH,
                                          { blrc::ImgFmt::RGBA8,        // a_r, a_g, a_b, roughness
                                            blrc::ImgFmt::RGBA16F,      // n_r, n_g, n_b, metallic
                                            blrc::ImgFmt::Depth32F} }); // depth
    }

    void Execute(blrc::Scene& scene, blrc::RenderContext& renderCtx) override
    {
        m_fbo->Bind(); 

        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LESS);
        glEnable(GL_CULL_FACE);
        glCullFace(GL_BACK);
        
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        blrc::Renderer::UpdateCameraUBO(*scene.GetCam());

        m_gShader->Bind(); 

        blrc::Renderer::DrawQueue(blrc::RenderQueueType::OPAQUE, nullptr);

        m_fbo->Unbind();


        renderCtx.Set("G_ALBEDO_ROUGH", m_fbo->GetColorAttachmentID(0));
        renderCtx.Set("G_NORMAL_METAL", m_fbo->GetColorAttachmentID(1));
        renderCtx.Set("G_DEPTH",        m_fbo->GetDepthAttachmentID());
    }

    virtual void OnResize(uint32_t width, uint32_t height) override
    {
        m_fbo->Resize(width, height);
    }

    void Shutdown() override
    {
    }

private:
    uint32_t m_initW;
    uint32_t m_initH;

    blrc::Ref<blrc::FrameBuffer> m_fbo;
    blrc::Ref<blrc::Shader> m_gShader;
};