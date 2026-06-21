// shadow_mask_pass.hpp

#pragma once

#include <bolero.hpp>

namespace blrc = blr::core;

class ShadowMaskPass : public blrc::RenderPass
{
public:
    ShadowMaskPass(uint32_t initW, uint32_t initH, const blrc::Ref<blrc::Shader>& shadowMaskShader)
    : RenderPass("Shadow Mask Pass")
    , m_initW(initW)
    , m_initH(initH)
    , m_shadowMaskShader(shadowMaskShader)
    {
    }

    void Init() override
    {
        m_fbo = blrc::FrameBuffer::Create({ m_initW, m_initH,
                                          { blrc::ImgFmt::RGBA16F,       // R: dir_0,   G: dir_1,   B: dir_2,   A: dir_3
                                            blrc::ImgFmt::RGBA16F,       //    spot_0,     spot_1,     spot_2,     spot_3
                                            blrc::ImgFmt::RGBA16F} });   //    point_0,    point_1,    point_2,    point_3
    }

    void Execute(blrc::Scene& scene, blrc::RenderContext& renderCtx) override
    {
        glDisable(GL_DEPTH_TEST);     
        glDisable(GL_CULL_FACE);

        m_fbo->Bind();

        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);


        m_shadowMaskShader->Bind();

        m_shadowMaskShader->SetFloat("u_LightSize", renderCtx.Get<float>("u_LightSize", 0.05f));

        glBindTextureUnit(1, renderCtx.Get<GLuint>("G_NORMAL_METAL"));
        glBindTextureUnit(2, renderCtx.Get<GLuint>("G_DEPTH"));


        // Directional Shadows (Slots 10 - 13)
        int numDirShadows = renderCtx.Get<int>("u_NumDirShadows"); 
        numDirShadows = std::min(numDirShadows, 4);
        for (int i = 0; i < numDirShadows; i++)
        {
            glBindTextureUnit(10 + i, renderCtx.Get<GLuint>("u_DirDepthMapTex_" + std::to_string(i)));
            m_shadowMaskShader->SetMat4("u_DirLightSpaceMat[" + std::to_string(i) + "]", renderCtx.Get<blrc::mat4>("u_DirLightSpaceMat_" + std::to_string(i)));
        }
        // Spot Shadows (Slots 14 - 17)
        int numSpotShadows = renderCtx.Get<int>("u_NumSpotShadows");
        numSpotShadows = std::min(numSpotShadows, 4);
        for (int i = 0; i < numSpotShadows; i++)
        {
            glBindTextureUnit(14 + i, renderCtx.Get<GLuint>("u_SpotDepthMapTex_" + std::to_string(i)));
            m_shadowMaskShader->SetMat4("u_SpotLightSpaceMat[" + std::to_string(i) + "]", renderCtx.Get<blrc::mat4>("u_SpotLightSpaceMat_" + std::to_string(i)));
        }
        // Point Shadows (Slots 18 - 21)
        int numPointShadows = renderCtx.Get<int>("u_NumPointShadows");
        numPointShadows = std::min(numPointShadows, 4);
        for (int i = 0; i < numPointShadows; i++)
        {
            glBindTextureUnit(18 + i, renderCtx.Get<GLuint>("u_PointDepthMapTex_" + std::to_string(i)));
        }

        auto sceneCam = scene.GetCam();
        m_shadowMaskShader->SetMat4("u_InvView", blrc::Inverse(sceneCam->GetViewMat()));
        m_shadowMaskShader->SetMat4("u_InvProj", blrc::Inverse(sceneCam->GetProjMat()));

        blrc::Renderer::DrawFullscreenQuad();

        m_shadowMaskShader->Unbind();


        m_fbo->Unbind();


        renderCtx.Set("DIR_SHADOW_MASK",   m_fbo->GetColorAttachmentID(0));   // u_DirShadowMask
        renderCtx.Set("SPOT_SHADOW_MASK",  m_fbo->GetColorAttachmentID(1));   // u_SpotShadowMask
        renderCtx.Set("POINT_SHADOW_MASK", m_fbo->GetColorAttachmentID(2));   // u_PointShadowMask
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
    blrc::Ref<blrc::Shader> m_shadowMaskShader;
};