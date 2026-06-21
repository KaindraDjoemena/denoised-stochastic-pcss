// lighting_pass.hpp

#pragma once

#include <bolero.hpp>

namespace blrc = blr::core;

class LightingPass : public blrc::RenderPass
{
public:
    LightingPass(uint32_t initW, uint32_t initH, const blrc::Ref<blrc::Shader>& lightShader, const blrc::Ref<blrc::Shader>& skyboxShader)
    : RenderPass("Lighting Pass")
    , m_initW(initW)
    , m_initH(initH)
    , m_lightShader(lightShader)
    , m_skyboxShader(skyboxShader)
    {
    }

    void Init() override
    {
        m_fbo = blrc::FrameBuffer::Create({ m_initW, m_initH, { blrc::ImgFmt::RGBA16F} });
    }

    void Execute(blrc::Scene& scene, blrc::RenderContext& renderCtx) override
    {
        glDisable(GL_DEPTH_TEST);     
        glDisable(GL_CULL_FACE);

        m_fbo->Bind();


        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        
        // Skybox
        m_skyboxShader->Bind();
        glBindTextureUnit(6, renderCtx.Get<GLuint>("u_PrefilterMap"));
        
        m_skyboxShader->SetFloat("u_EnvironmentBlur", renderCtx.Get<float>("u_EnvironmentBlur", 0.9f));
        
        blrc::Renderer::DrawCube();


        m_lightShader->Bind();

        // G-Buffer
        glBindTextureUnit(0, renderCtx.Get<GLuint>("G_ALBEDO_ROUGH"));
        glBindTextureUnit(1, renderCtx.Get<GLuint>("G_NORMAL_METAL"));
        glBindTextureUnit(2, renderCtx.Get<GLuint>("G_DEPTH"));
        
        // IBL Maps
        glBindTextureUnit(5, renderCtx.Get<GLuint>("u_IrradianceMap"));
        glBindTextureUnit(6, renderCtx.Get<GLuint>("u_PrefilterMap"));
        glBindTextureUnit(7, renderCtx.Get<GLuint>("u_BrdfLut"));

        // Shadwow Masks
        glBindTextureUnit(10, renderCtx.Get<GLuint>("DIR_SHADOW_MASK"));
        glBindTextureUnit(11, renderCtx.Get<GLuint>("SPOT_SHADOW_MASK"));
        glBindTextureUnit(12, renderCtx.Get<GLuint>("POINT_SHADOW_MASK"));

        // Denoised Shadow Masks
        glBindTextureUnit(13, renderCtx.Get<GLuint>("DENOISED_DIR_SHADOW_MASK"));
        glBindTextureUnit(14, renderCtx.Get<GLuint>("DENOISED_SPOT_SHADOW_MASK"));
        glBindTextureUnit(15, renderCtx.Get<GLuint>("DENOISED_POINT_SHADOW_MASK"));

        float splitX = renderCtx.Get<float>("u_SplitX", 0.5f);
        m_lightShader->SetFloat("u_SplitX", splitX);


        auto sceneCam = scene.GetCam();
        m_lightShader->SetMat4("u_InvView", blrc::Inverse(sceneCam->GetViewMat()));
        m_lightShader->SetMat4("u_InvProj", blrc::Inverse(sceneCam->GetProjMat()));

        blrc::Renderer::DrawFullscreenQuad();

        m_lightShader->Unbind();


        m_fbo->Unbind();


        renderCtx.Set("OPAQUE_PASS_TEX", m_fbo->GetColorAttachmentID(0));
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
    blrc::Ref<blrc::Shader> m_lightShader;
    blrc::Ref<blrc::Shader> m_skyboxShader;
};