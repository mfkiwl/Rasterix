// RasterIX
// https://github.com/ToNi3141/RasterIX
// Copyright (c) 2024 ToNi3141

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

#ifndef LIGHTING_HPP
#define LIGHTING_HPP

#include "Enums.hpp"
#include "Types.hpp"
#include "math/Vec.hpp"
#include <array>

namespace rr::lighting
{

struct LightingData
{
    static constexpr std::size_t MAX_LIGHTS { 8 };
    struct MaterialConfig
    {
        Vec4 emissiveColor { { 0.0f, 0.0f, 0.0f, 1.0f } };
        Vec4 ambientColor { { 0.2f, 0.2f, 0.2f, 1.0 } };
        Vec4 ambientColorScene { { 0.2f, 0.2f, 0.2f, 1.0f } };
        Vec4 diffuseColor { { 0.8f, 0.8f, 0.8f, 1.0 } };
        Vec4 specularColor { { 0.0f, 0.0f, 0.0f, 1.0 } };
        float specularExponent { 0.0f };
    };

    struct LightConfig
    {
        Vec4 ambientColor { { 0.0f, 0.0f, 0.0f, 1.0f } };
        Vec4 diffuseColor { { 1.0f, 1.0f, 1.0f, 1.0f } }; // For other lights than light0 the default value is {{0.0f, 0.0f, 0.0f, 1.0f}}
        Vec4 specularColor { { 1.0f, 1.0f, 1.0f, 1.0f } }; // For other lights than light0 the default value is {{0.0f, 0.0f, 0.0f, 1.0f}}
        Vec4 position { { 0.0f, 0.0f, 1.0f, 0.0f } };
        Vec3 spotlightDirection { { 0.0f, 0.0f, -1.0f } };
        float spotlightExponent { 0.0f };
        float spotlightCutoff { 180.0f };
        float constantAttenuation { 1.0f };
        float linearAttenuation { 0.0f };
        float quadraticAttenuation { 0.0f };

        static constexpr bool localViewer { false }; // Not necessary, local viewer is not supported in OpenGL ES because of performance degradation (GL_LIGHT_MODEL_LOCAL_VIEWER)

        Vec4 preCalcDirectionalLightDir {};
        Vec4 preCalcHalfWayVectorInfinite {};

        void preCalcVectors()
        {
            // Directional Light Direction
            preCalcDirectionalLightDir = position;
            preCalcDirectionalLightDir.unit();

            // Half Way Vector from infinite viewer
            const Vec4 pointEye { 0.0f, 0.0f, 1.0f, 1.0f };
            preCalcHalfWayVectorInfinite = preCalcDirectionalLightDir;
            preCalcHalfWayVectorInfinite += pointEye;
            preCalcHalfWayVectorInfinite.unit();
        }
    };

    std::array<LightConfig, MAX_LIGHTS> lights {};
    MaterialConfig material {};
    std::array<bool, MAX_LIGHTS> lightEnable {};
    bool lightingEnabled { false };
    bool enableColorMaterialEmission { false };
    bool enableColorMaterialAmbient { false };
    bool enableColorMaterialDiffuse { false };
    bool enableColorMaterialSpecular { false };
};

class LightingCalc
{
public:
    LightingCalc(const LightingData& lightingData)
        : m_data { lightingData }
    {
    }

    void calculateSceneLight(
        Vec4& __restrict sceneLight,
        const Vec4& emissiveColor,
        const Vec4& ambientColor,
        const Vec4& ambientColorScene) const;

    void calculateLight(
        Vec4& __restrict color,
        const LightingData::LightConfig& lightConfig,
        const float materialSpecularExponent,
        const Vec4& materialAmbientColor,
        const Vec4& materialDiffuseColor,
        const Vec4& materialSpecularColor,
        const Vec4& v0,
        const Vec4& n0) const;

    void calculateLights(
        Vec4& __restrict color,
        const Vec4& triangleColor,
        const Vec4& vertex,
        const Vec3& normal) const;

private:
    const LightingData& m_data;
};

class LightingSetter
{
public:
    LightingSetter(LightingData& lightingData);

    bool lightingEnabled() const { return m_data.lightingEnabled; }

    void enableLighting(bool enable);
    void setEmissiveColorMaterial(const Vec4& color);
    void setAmbientColorMaterial(const Vec4& color);
    void setAmbientColorScene(const Vec4& color);
    void setDiffuseColorMaterial(const Vec4& color);
    void setSpecularColorMaterial(const Vec4& color);
    void setSpecularExponentMaterial(const float val);
    void enableLight(const std::size_t light, const bool enable);
    void setAmbientColorLight(const std::size_t light, const Vec4& color);
    void setDiffuseColorLight(const std::size_t light, const Vec4& color);
    void setSpecularColorLight(const std::size_t light, const Vec4& color);
    void setPosLight(const std::size_t light, const Vec4& pos);
    void setConstantAttenuationLight(const std::size_t light, const float val);
    void setLinearAttenuationLight(const std::size_t light, const float val);
    void setQuadraticAttenuationLight(const std::size_t light, const float val);

    void setColorMaterialTracking(const Face face, const ColorMaterialTracking material);
    void enableColorMaterial(const bool enable);

private:
    void enableColorMaterial(bool emission, bool ambient, bool diffuse, bool specular);

    LightingData& m_data;

    // Color material
    bool m_enableColorMaterial { false };
    ColorMaterialTracking m_colorMaterialTracking { ColorMaterialTracking::AMBIENT_AND_DIFFUSE };
    Face m_colorMaterialFace { Face::FRONT_AND_BACK };
};

} // namespace rr::lighting
#endif // LIGHTING_HPP