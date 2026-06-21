// denoiser_pass.hpp

#pragma once

#include <bolero.hpp>

namespace blrc = blr::core;

class DenoiserPass : public blrc::RenderPass
{
public:
    DenoiserPass(uint32_t initW, uint32_t initH, const blrc::Ref<blrc::Shader>& denoiserShader)
    : RenderPass("Denoiser Pass")
    , m_initW(initW)
    , m_initH(initH)
    , m_denoiserShader(denoiserShader)
    {
    }

    void Init() override
    {
        m_hFbo = blrc::FrameBuffer::Create({ m_initW, m_initH,
                                          { blrc::ImgFmt::RGBA16F,       // R: dir_0,   G: dir_1,   B: dir_2,   A: dir_3
                                            blrc::ImgFmt::RGBA16F,       //    spot_0,     spot_1,     spot_2,     spot_3
                                            blrc::ImgFmt::RGBA16F} });   //    point_0,    point_1,    point_2,    point_3
        m_hvFbo = blrc::FrameBuffer::Create({ m_initW, m_initH,
                                          { blrc::ImgFmt::RGBA16F,       // R: dir_0,   G: dir_1,   B: dir_2,   A: dir_3
                                            blrc::ImgFmt::RGBA16F,       //    spot_0,     spot_1,     spot_2,     spot_3
                                            blrc::ImgFmt::RGBA16F} });   //    point_0,    point_1,    point_2,    point_3
    }

    void Execute(blrc::Scene& scene, blrc::RenderContext& renderCtx) override
    {
        bool enabled = renderCtx.Get<bool>("ENABLE_DENOISER", true);
        if (!enabled)
        {
            renderCtx.Set("DENOISED_DIR_SHADOW_MASK",   renderCtx.Get<GLuint>("DIR_SHADOW_MASK"));
            renderCtx.Set("DENOISED_SPOT_SHADOW_MASK",  renderCtx.Get<GLuint>("SPOT_SHADOW_MASK"));
            renderCtx.Set("DENOISED_POINT_SHADOW_MASK", renderCtx.Get<GLuint>("POINT_SHADOW_MASK"));
            return;
        }


        m_denoiserShader->Bind();

        m_denoiserShader->SetUInt("u_Radius",        renderCtx.Get<int>("u_DenoiserRadius", 3));
        m_denoiserShader->SetFloat("u_SpatialSigma", renderCtx.Get<float>("u_SpatialSigma", 2.0f));
        m_denoiserShader->SetFloat("u_NormalSigma",  renderCtx.Get<float>("u_DepthSigma", 0.05f));
        m_denoiserShader->SetFloat("u_DepthSigma",   renderCtx.Get<float>("u_NormalSigma", 32.0f));

        glBindTextureUnit(1, renderCtx.Get<GLuint>("G_NORMAL_METAL"));
        glBindTextureUnit(2, renderCtx.Get<GLuint>("G_DEPTH"));


        // ===== HORIZONTAL BLUR PASS =====
        m_hFbo->Bind();

        // Original Shadwow Masks
        glBindTextureUnit(10, renderCtx.Get<GLuint>("DIR_SHADOW_MASK"));
        glBindTextureUnit(11, renderCtx.Get<GLuint>("SPOT_SHADOW_MASK"));
        glBindTextureUnit(12, renderCtx.Get<GLuint>("POINT_SHADOW_MASK"));
        // Horizontal Filtering
        m_denoiserShader->SetVec4("u_Direction", blrc::vec4(1.0 / float(m_initW), 0.0, 0.0, 0.0));

        blrc::Renderer::DrawFullscreenQuad();
        
        m_hFbo->Unbind();
        
        
        // ===== HORIZONTAL + VERTICAL BLUR PASS =====
        m_hvFbo->Bind();
        
        // Horizontally Blurred Shadow Masks 
        glBindTextureUnit(10, m_hFbo->GetColorAttachmentID(0));
        glBindTextureUnit(11, m_hFbo->GetColorAttachmentID(1));
        glBindTextureUnit(12, m_hFbo->GetColorAttachmentID(2));
        // Verticcal Filtering
        m_denoiserShader->SetVec4("u_Direction", blrc::vec4(0.0, 1.0 / float(m_initH), 0.0, 0.0));
        
        blrc::Renderer::DrawFullscreenQuad();

        m_hvFbo->Unbind();
        
        
        m_denoiserShader->Unbind();


        renderCtx.Set("DENOISED_DIR_SHADOW_MASK",   m_hvFbo->GetColorAttachmentID(0));   // u_DenoisedDirShadowMask
        renderCtx.Set("DENOISED_SPOT_SHADOW_MASK",  m_hvFbo->GetColorAttachmentID(1));   // u_DenoisedSpotShadowMask
        renderCtx.Set("DENOISED_POINT_SHADOW_MASK", m_hvFbo->GetColorAttachmentID(2));   // u_DenoisedPointShadowMask
    }

    virtual void OnResize(uint32_t width, uint32_t height) override
    {
        m_hFbo->Resize(width, height);
        m_hvFbo->Resize(width, height);
    }

    void Shutdown() override
    {
    }

private:
    uint32_t m_initW;
    uint32_t m_initH;

    blrc::Ref<blrc::FrameBuffer> m_hFbo;
    blrc::Ref<blrc::FrameBuffer> m_hvFbo;
    blrc::Ref<blrc::Shader> m_denoiserShader;
};