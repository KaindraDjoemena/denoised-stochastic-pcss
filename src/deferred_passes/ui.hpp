// passes/ui.hpp

#pragma once

#include <bolero.hpp>
#include "ui/ui.hpp"

#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>


namespace blrc = blr::core;

class UIPass : public blrc::RenderPass
{
public:
    UIPass(GLFWwindow* window, const std::vector<blrc::Ref<blrc::RenderPass>>& passes)
    : RenderPass("UI Pass")
    , m_window(window)
    , m_passes(passes)
    {
    }

    void Init() override
    {
        m_ui.Init(m_window);
    }

    void Execute(blrc::Scene& scene, blrc::RenderContext& renderCtx) override
    {
        m_ui.BeginFrame();


        m_ui.DrawPipelineStats(scene, m_passes);

        m_ui.DrawProperties(scene, renderCtx);

        // ===== SPLIT SCREEN =====
        ImGui::Spacing();
        ImGui::SeparatorText("Split Screen");
        {
            float splitX = renderCtx.Get<float>("u_SplitX", 0.5f);
            if (ImGui::SliderFloat("Split", &splitX, 0.0, 1.0, "%.2f"))
            {
                renderCtx.Set("u_SplitX", splitX, blrc::Lifetime::PERSISTENT);
            }

            // Draw line
            ImVec2 screenSize = ImGui::GetIO().DisplaySize;
            ImVec2 top    = ImVec2(splitX * screenSize.x, 0.0f);
            ImVec2 bottom = ImVec2(splitX * screenSize.x, screenSize.y);
            ImGui::GetForegroundDrawList()->AddLine(top, bottom, IM_COL32(255, 0, 255, 255), 3.0f);
        }

        // ===== DENOISER SETTINGS =====
        ImGui::Spacing();
        ImGui::SeparatorText("Denoiser");
        {
            bool enabled = renderCtx.Get<bool>("ENABLE_DENOISER", true);
            if (ImGui::Checkbox("Enable Bilateral Blur", &enabled))
                renderCtx.Set("ENABLE_DENOISER", enabled, blrc::Lifetime::PERSISTENT);

            if (enabled)
            {
                int radius = renderCtx.Get<int>("u_DenoiserRadius", 3);
                if (ImGui::SliderInt("Radius", &radius, 1, 10))
                    renderCtx.Set("u_DenoiserRadius", radius, blrc::Lifetime::PERSISTENT);

                float spatial = renderCtx.Get<float>("u_SpatialSigma", 2.0f);
                if (ImGui::SliderFloat("Spatial Sigma", &spatial, 0.1f, 10.0f, "%.2f"))
                    renderCtx.Set("u_SpatialSigma", spatial, blrc::Lifetime::PERSISTENT);

                float depth = renderCtx.Get<float>("u_DepthSigma", 0.05f);
                if (ImGui::SliderFloat("Depth Sigma", &depth, 0.001f, 0.5f, "%.4f", ImGuiSliderFlags_Logarithmic))
                    renderCtx.Set("u_DepthSigma", depth, blrc::Lifetime::PERSISTENT);

                float normal = renderCtx.Get<float>("u_NormalSigma", 32.0f);
                if (ImGui::SliderFloat("Normal Sigma", &normal, 1.0f, 128.0f, "%.1f"))
                    renderCtx.Set("u_NormalSigma", normal, blrc::Lifetime::PERSISTENT);
            }
        }

        // ===== PCSS SETTINGS =====
        ImGui::Spacing();
        ImGui::SeparatorText("PCSS");
        {
            float lightSize  = renderCtx.Get<float>("u_LightSize", 0.05f);
            if (ImGui::SliderFloat("Light Size", &lightSize, 0.001f, 0.5f, "%.4f", ImGuiSliderFlags_Logarithmic))
                renderCtx.Set("u_LightSize", lightSize, blrc::Lifetime::PERSISTENT);
        }

        m_ui.EndFrame();
    }

    virtual void OnResize(uint32_t width, uint32_t height) override
    {
    }

    void Shutdown() override
    {
        m_ui.Shutdown();
    }

private:
    blrc::UI m_ui;

    GLFWwindow* m_window;
    const std::vector<blrc::Ref<RenderPass>>& m_passes;
};