// Rasterix
// https://github.com/ToNi3141/Rasterix
// Copyright (c) 2022 ToNi3141

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

#include "VertexPipeline.hpp"
#include "Vec.hpp"
#include "Veci.hpp"
#include <string.h>
#include <stdlib.h>
#include "Rasterizer.hpp"

// The Arduino IDE will produce compile errors when using std::min and std::max
#include <algorithm>    // std::max
#define max std::max
#define min std::min

#define __glPi 3.14159265358979323846f

VertexPipeline::VertexPipeline(PixelPipeline& renderer)
    : m_renderer(renderer)
{
    m_t.identity();
    m_m.identity();
    m_p.identity();
    m_n.identity();
}

// Might be a faster version than the other implementation.
// Needs to be profiled. Leave it for now as dead code.
// bool VertexPipeline::drawObj(const RenderObj &obj)
// {
//     recalculateMatrices();
//     for (uint32_t it = 0; it < obj.getCount(); it += VERTEX_BUFFER_SIZE)
//     {
//         const std::size_t diff = obj.getCount() - it;
//         const std::size_t cnt = min(VERTEX_BUFFER_SIZE + VERTEX_OVERLAP, diff);

//         if (diff <= VERTEX_OVERLAP)
//         {
//             // A triangle needs at least three points to be constructed. There is a overlap between two
//             // sections. Normally the overlap must always be two, otherwise there is an extra vertex, which can't
//             // be used. This can happen when the asserts for VERTEX_BUFFER_SIZE are not full filled.
//             break;
//         }

//         Vec4Array transformedVertex;
//         Vec4Array transformedColor;
//         Vec4Array transformedTexCoord;
//         Vec3Array transformedNormal;
//         for (uint32_t i = 0, itCnt = it; i < cnt; i++, itCnt++)
//         {
//             const uint32_t index = obj.getIndex(itCnt);

//             Vec4 v;
//             Vec4 c;
//             if (obj.colorArrayEnabled())
//             {
//                 obj.getColor(c, index);
//             }
//             else
//             {
//                 // If no color is defined, use the global color
//                 c = obj.getVertexColor();
//             }

//             if (obj.vertexArrayEnabled())
//             {
//                 obj.getVertex(v, index);
//                 m_t.transform(transformedVertex[i], v);
//             }

//             if (obj.texCoordArrayEnabled())
//             {
//                 obj.getTexCoord(transformedTexCoord[i], index);
//             }
//             m_texGen.calculateTexGenCoords(m_m, transformedTexCoord[i], v);


//             if (m_lighting.lightingEnabled())
//             {
//                 Vec4 vl;
//                 Vec3 nl;
//                 Vec3 n;
//                 if (obj.normalArrayEnabled())
//                 {
//                     obj.getNormal(n, index);
//                     m_n.transform(nl, n);
//                     // In OpenGL this step can be turned on and off with GL_NORMALIZE, also there is GL_RESCALE_NORMAL which offers a faster way
//                     // which only works with uniform scales. For now this is constantly enabled because it is usually what someone want.
//                     nl.normalize();
//                 }
//                 if (obj.vertexArrayEnabled())
//                 {
//                     m_m.transform(vl, v);
//                 }

//                 m_lighting.calculateLights(transformedColor[i], c, vl, nl);
//             }
//             else
//             {
//                 transformedColor[i] = c;
//             }
//         }

//         const bool ret = drawTriangleArray(
//             transformedVertex,
//             transformedColor,
//             transformedTexCoord,
//             cnt,
//             obj.getDrawMode()
//         );
//         if (!ret)
//         {
//             return false;
//         }
//     }
//     return true;
// }

bool VertexPipeline::drawObj(const RenderObj &obj)
{
    recalculateMatrices();
    if (!m_renderer.updatePipeline()) 
    {
        return false;
    }

    for (std::size_t it = 0; it < obj.getCount(); it += VERTEX_BUFFER_SIZE)
    {
        const std::size_t diff = obj.getCount() - it;
        const std::size_t cnt = min(VERTEX_BUFFER_SIZE + VERTEX_OVERLAP, diff);

        if (diff <= VERTEX_OVERLAP)
        {
            // A triangle needs at least three points to be constructed. There is a overlap between two
            // sections. Normally the overlap must always be two, otherwise there is an extra vertex, which can't
            // be used. This can happen when the asserts for VERTEX_BUFFER_SIZE are not full filled.
            break;
        }

        Vec4Array vertex;
        Vec4Array color;
        Vec4Array texCoord;
        Vec3Array normal;

        Vec4Array transformedVertex;
        Vec4Array transformedColor;
        Vec4Array transformedTexCoord;
        Vec3Array transformedNormal;

        loadVertexData(obj, vertex, color, normal, texCoord, it, cnt);

        transform(
            transformedVertex,
            transformedColor,
            transformedNormal,
            transformedTexCoord,
            obj.vertexArrayEnabled(),
            obj.colorArrayEnabled(),
            obj.normalArrayEnabled(),
            obj.texCoordArrayEnabled(),
            vertex,
            color,
            normal,
            texCoord,
            obj.getVertexColor(),
            cnt
        );

        const bool ret = drawTriangleArray(
            transformedVertex,
            transformedColor,
            transformedTexCoord,
            cnt,
            obj.getDrawMode()
        );
        if (!ret)
        {
            return false;
        }
    }
    return true;
}

bool VertexPipeline::drawTriangle(const Triangle& triangle)
{
    Clipper::ClipVertList vertList;
    Clipper::ClipVertList texCoordList;
    Clipper::ClipVertList colorList;
    Clipper::ClipVertList vertListBuffer;
    Clipper::ClipVertList texCoordListBuffer;
    Clipper::ClipVertList colorListBuffer;

    vertList[0] = triangle.v0;
    vertList[1] = triangle.v1;
    vertList[2] = triangle.v2;

    texCoordList[0] = triangle.tc0;
    texCoordList[1] = triangle.tc1;
    texCoordList[2] = triangle.tc2;

    colorList[0] = triangle.color0;
    colorList[1] = triangle.color1;
    colorList[2] = triangle.color2;

    // Because if flat shading, the color doesn't have to be interpolated during clipping, so it can be ignored for now...
    auto [vertListSize, vertListClipped, texCoordListClipped, colorListClipped] = Clipper::clip(vertList, vertListBuffer, texCoordList, texCoordListBuffer, colorList, colorListBuffer);

    // Calculate for every vertex the perspective division and also apply the viewport transformation
    for (uint8_t i = 0; i < vertListSize; i++)
    {
        // Perspective division
        vertListClipped[i].perspectiveDivide();

        // Perspective correction of the texture coordinates
        texCoordListClipped[i].mul(vertListClipped[i][3]); // since w is already divided, just multiply the 1/w to all elements. Saves one division.
        // TODO: Perspective correction of the color 
        // Each texture uses it's own scaled w (basically q*w). Therefore the hardware must 
        // interpolate (q*w) for each texture. w alone is not enough because OpenGL allows to set q coordinate.

        // Viewport transformation of the vertex
        viewportTransform(vertListClipped[i]);
    }

    // Cull triangle
    if (m_enableCulling)
    {
        // Check only one triangle in the clipped list. The triangles are sub divided, but not rotated. So if one triangle is 
        // facing backwards, then all in the clipping list will do this and vice versa.
        const float edgeVal = Rasterizer::edgeFunctionFloat(vertListClipped[0], vertListClipped[1], vertListClipped[2]);
        const Face currentOrientation = (edgeVal <= 0.0f) ? Face::BACK : Face::FRONT;
        if (currentOrientation != m_cullMode)
            return true;
    }
    
    // Render the triangle
    for (uint8_t i = 3; i <= vertListSize; i++)
    {
        // For a triangle we need atleast 3 vertices. Also treat the clipped list from the clipping as a
        // triangle fan where vert zero is always the center of this fan
        const bool success = m_renderer.drawTriangle(vertListClipped[0],
                vertListClipped[i - 2],
                vertListClipped[i - 1],
                texCoordListClipped[0],
                texCoordListClipped[i - 2],
                texCoordListClipped[i - 1],
                colorListClipped[0],
                colorListClipped[i - 2],
                colorListClipped[i - 1]);
        if (!success)
        {
            return false;
        }
    }
    return true;
}

void VertexPipeline::loadVertexData(const RenderObj& obj, Vec4Array& vertex, Vec4Array& color, Vec3Array& normal, Vec4Array& tex, const std::size_t offset, const std::size_t count)
{
    for (uint32_t o = offset, i = 0; i < count; o++, i++)
    {
        const uint32_t index = obj.getIndex(o);
        if (obj.colorArrayEnabled())
        {
            obj.getColor(color[i], index);
        }
        if (obj.vertexArrayEnabled())
        {
            obj.getVertex(vertex[i], index);
        }
        if (obj.normalArrayEnabled())
        {
            obj.getNormal(normal[i], index);
        }
        if (obj.texCoordArrayEnabled())
        {
            obj.getTexCoord(tex[i], index);
        }
    }
}

void VertexPipeline::transform(
    Vec4Array& transformedVertex, 
    Vec4Array& transformedColor, 
    Vec3Array& transformedNormal, 
    Vec4Array& transformedTex, 
    const bool enableVertexArray,
    const bool enableColorArray,
    const bool enableNormalArray,
    const bool enableTexArray,
    const Vec4Array& vertex, 
    const Vec4Array& color, 
    const Vec3Array& normal, 
    const Vec4Array& tex,
    const Vec4& vertexColor,
    const std::size_t count)
{
    if (m_lighting.lightingEnabled())
    {
        if (enableVertexArray)
            m_m.transform(transformedVertex.data(), vertex.data(), count);
        if (enableNormalArray)
            m_n.transform(transformedNormal.data(), normal.data(), count);
        
        for (std::size_t i = 0; i < count; i++)
        {
            Vec4 c;
            if (enableColorArray)
            {
                c = color[i];
            }
            else
            {
                c = vertexColor;
            }

            if (enableNormalArray)
                transformedNormal[i].normalize();
            m_lighting.calculateLights(transformedColor[i], c, transformedVertex[i], transformedNormal[i]);
        }
    }
    else
    {
        for (std::size_t i = 0; i < count; i++)
        {
            if (enableColorArray)
            {
                transformedColor[i] = color[i];
            }
            else
            {
                transformedColor[i] = vertexColor;
            }
        }
    }

    for (std::size_t i = 0; i < count; i++)
    {
        if (enableTexArray)
        {
            transformedTex[i] = tex[i];
        }
        else
        {
            transformedTex[i].initHomogeneous();
        }
        m_texGen.calculateTexGenCoords(m_m, transformedTex[i], vertex[i]);
    }

    if (enableVertexArray)
        m_t.transform(transformedVertex.data(), vertex.data(), count);
}

bool VertexPipeline::drawTriangleArray(
    const Vec4Array& vertex, 
    const Vec4Array& color, 
    const Vec4Array& tex, 
    const std::size_t count, 
    const RenderObj::DrawMode drawMode)
{
    static_assert(VERTEX_OVERLAP == 2, "VERTEX_OVERLAP must be at least two");
    for (uint32_t i = 0; i < (count - VERTEX_OVERLAP); )
    {
        uint32_t index0;
        uint32_t index1;
        uint32_t index2;
        switch (drawMode) {
        case RenderObj::DrawMode::TRIANGLES:
            index0 = (i);
            index1 = (i + 1);
            index2 = (i + 2);
            i += 3;
            break;
        case RenderObj::DrawMode::TRIANGLE_FAN:
            index0 = (0);
            index1 = (i + 1);
            index2 = (i + 2);
            i += 1;
            break;
        case RenderObj::DrawMode::TRIANGLE_STRIP:
            if (i & 0x1)
            {
                index0 = (i + 1);
                index1 = (i);
                index2 = (i + 2);
            }
            else
            {
                index0 = (i);
                index1 = (i + 1);
                index2 = (i + 2);
            }
            i += 1;
            break;
        case RenderObj::DrawMode::QUAD_STRIP:
            if (i & 0x2)
            {
                index0 = (i + 1);
                index1 = (i);
                index2 = (i + 2);
            }
            else
            {
                index0 = (i);
                index1 = (i + 1);
                index2 = (i + 2);
            }
            i += 1;
            break;
        default:
            break;
        }


        Triangle triangle {
            vertex[index0],
            vertex[index1],
            vertex[index2],
            tex[index0],
            tex[index1],
            tex[index2],
            color[index0],
            color[index1],
            color[index2]
        };


        if (!drawTriangle(triangle))
        {
            return false;
        }
    }
    return true;
}

void VertexPipeline::viewportTransform(Vec4 &v0, Vec4 &v1, Vec4 &v2)
{
    v0[0] = ((v0[0] + 1.0f) * m_viewportWidth * 0.5f) + m_viewportX;
    v1[0] = ((v1[0] + 1.0f) * m_viewportWidth * 0.5f) + m_viewportX;
    v2[0] = ((v2[0] + 1.0f) * m_viewportWidth * 0.5f) + m_viewportX;

    v0[1] = ((v0[1] + 1.0f) * m_viewportHeight * 0.5f) + m_viewportY;
    v1[1] = ((v1[1] + 1.0f) * m_viewportHeight * 0.5f) + m_viewportY;
    v2[1] = ((v2[1] + 1.0f) * m_viewportHeight * 0.5f) + m_viewportY;

    v0[2] = (((v0[2] + 1.0f) * 0.25f)) * (m_depthRangeZFar - m_depthRangeZNear);
    v1[2] = (((v1[2] + 1.0f) * 0.25f)) * (m_depthRangeZFar - m_depthRangeZNear);
    v2[2] = (((v2[2] + 1.0f) * 0.25f)) * (m_depthRangeZFar - m_depthRangeZNear);

    // This is a possibility just to calculate the real z value but is not needed for the rasterizer
    //    float n = 0.1;
    //    float f = 100;
    //    float z_ndc0 = 2.0 * v0f[2] - 1.0;
    //    v0f[2] = 2.0 * n * f / (f + n - z_ndc0 * (f - n));
    //    float z_ndc1 = 2.0 * v1f[2] - 1.0;
    //    v1f[2] = 2.0 * n * f / (f + n - z_ndc1 * (f - n));
    //    float z_ndc2 = 2.0 * v2f[2] - 1.0;
    //    v2f[2] = 2.0 * n * f / (f + n - z_ndc2 * (f - n));

}

void VertexPipeline::viewportTransform(Vec4 &v)
{
    // v has the range from -1 to 1. When we multiply it, it has a range from -viewPortWidth/2 to viewPortWidth/2
    // With the addition we shift it from -viewPortWidth/2 to 0 + viewPortX
    v[0] = (((v[0] * m_viewportWidthHalf)) + m_viewportXShift);
    v[1] = (((v[1] * m_viewportHeightHalf)) + m_viewportYShift);
    // Alternative implementation which is basically doing the same but without precomputed variables
    // v[0] = (((v[0] + 1.0f) * m_viewportWidth * 0.5f) + m_viewportX);
    // v[1] = (((v[1] + 1.0f) * m_viewportHeight * 0.5f) + m_viewportY);
    v[2] = (((v[2] + 1.0f) * 0.25f)) * (m_depthRangeZFar - m_depthRangeZNear);
}


void VertexPipeline::setViewport(const int16_t x, const int16_t y, const int16_t width, const int16_t height)
{
    // Note: The screen resolution is width and height. But during view port transformation we are clamping between
    // 0 and height which means a effective screen resolution of height + 1. For instance, we have a resolution of
    // 480 x 272. The view port transformation would go from 0 to 480 which are then 481px. Thats the reason why we
    // decrement here the resolution by one.
    m_viewportHeight = height - 1;
    m_viewportWidth = width - 1;
    m_viewportX = x;
    m_viewportY = y;

    m_viewportHeightHalf = m_viewportHeight / 2.0f;
    m_viewportWidthHalf = m_viewportWidth / 2.0f;
    m_viewportXShift = m_viewportX + m_viewportWidthHalf;
    m_viewportYShift = m_viewportY + m_viewportHeightHalf;

}

void VertexPipeline::setDepthRange(const float zNear, const float zFar)
{
    m_depthRangeZFar = zFar;
    m_depthRangeZNear = zNear;
}

void VertexPipeline::setModelProjectionMatrix(const Mat44 &m)
{
    m_t = m;
}

void VertexPipeline::setModelMatrix(const Mat44 &m)
{
    m_m = m;
}

void VertexPipeline::setNormalMatrix(const Mat44& m)
{
    m_n = m;
}

void VertexPipeline::setCullMode(const VertexPipeline::Face mode)
{
    m_cullMode = mode;
}

void VertexPipeline::enableCulling(const bool enable)
{
    m_enableCulling = enable;
}

void VertexPipeline::multiply(const Mat44& mat)
{
    if (m_matrixMode == MatrixMode::MODELVIEW)
    {
        m_m = mat * m_m;
    }
    else
    {
        m_p = mat * m_p;
    }

    m_matricesOutdated = true;
}

void VertexPipeline::translate(const float x, const float y, const float z)
{
    Mat44 m;
    m.identity();
    m[3][0] = x;
    m[3][1] = y;
    m[3][2] = z;
    multiply(m);
    m_matricesOutdated = true;
}

void VertexPipeline::scale(const float x, const float y, const float z)
{
    Mat44 m;
    m.identity();
    m[0][0] = x;
    m[1][1] = y;
    m[2][2] = z;
    multiply(m);
    m_matricesOutdated = true;
}

void VertexPipeline::rotate(const float angle, const float x, const float y, const float z)
{
    float angle_rad = angle * (__glPi/180.0f);

    float c = cosf(angle_rad);
    float s = sinf(angle_rad);
    float t = 1.0f - c;

    Mat44 m
    {{{
        {c+x*x*t,   y*x*t+z*s,  z*x*t-y*s,  0.0f},
        {x*y*t-z*s, c+y*y*t,    z*y*t+x*s,  0.0f},
        {x*z*t+y*s, y*z*t-x*s,  z*z*t+c,    0.0f},
        {0.0f,      0.0f,       0.0f,       1.0f}
    }}};

    multiply(m);
    m_matricesOutdated = true;
}

void VertexPipeline::loadIdentity()
{
    if (m_matrixMode == MatrixMode::MODELVIEW)
    {
        m_m.identity();
    }
    else
    {
        m_p.identity();
    }
    m_matricesOutdated = true;
}

bool VertexPipeline::pushMatrix()
{
    if (m_matrixMode == MatrixMode::MODELVIEW)
    {
        if (m_mStackIndex < MODEL_MATRIX_STACK_DEPTH)
        {
            m_mStack[m_mStackIndex] = m_m;
            m_mStackIndex++;
            m_matricesOutdated = true;
        }
        else
        {
            return false;
        }
    }
    else if (m_matrixMode == MatrixMode::PROJECTION)
    {
        if (m_pStackIndex < PROJECTION_MATRIX_STACK_DEPTH)
        {
            m_pStack[m_pStackIndex] = m_p;
            m_pStackIndex++;
            m_matricesOutdated = true;
        }
        else
        {
            return false;
        }
    }
    return true;
}

bool VertexPipeline::popMatrix()
{
    if (m_matrixMode == MatrixMode::MODELVIEW)
    {
        if (m_mStackIndex > 0)
        {
            m_mStackIndex--;
            m_m = m_mStack[m_mStackIndex];
            m_matricesOutdated = true;
        }
        else
        {
            return false;
        }
    }
    else if (m_matrixMode == MatrixMode::PROJECTION)
    {
        if (m_pStackIndex > 0)
        {
            m_pStackIndex--;
            m_p = m_pStack[m_pStackIndex];
            m_matricesOutdated = true;
        }
        else
        {
            return false;
        }
    }

    return true;
}

const Mat44& VertexPipeline::getModelMatrix() const
{
    return m_m;
}

const Mat44& VertexPipeline::getProjectionMatrix() const
{
    return m_p;
}

void VertexPipeline::recalculateMatrices()
{
    if (m_matricesOutdated)
    {
        // Update transformation matrix
        Mat44 t{m_m};
        t *= m_p;
        setModelProjectionMatrix(t);
        setModelMatrix(m_m);

        Mat44 inv{m_m};
        inv.invert();
        inv.transpose();
        // Use the inverse transpose matrix for the normals. This is the standard way how OpenGL transforms normals
        setNormalMatrix(inv);

        m_matricesOutdated = false;
    }
}

void VertexPipeline::setMatrixMode(const MatrixMode matrixMode)
{
    m_matrixMode = matrixMode;
}

uint8_t VertexPipeline::getModelMatrixStackDepth()
{
    return MODEL_MATRIX_STACK_DEPTH;
}

uint8_t VertexPipeline::getProjectionMatrixStackDepth()
{
    return PROJECTION_MATRIX_STACK_DEPTH;
}

Lighting& VertexPipeline::getLighting()
{
    return m_lighting;
}

TexGen& VertexPipeline::getTexGen()
{
    return m_texGen;
}

void VertexPipeline::setColorMaterialTracking(const Face face, const ColorMaterialTracking material)
{
    switch (material) {
        case ColorMaterialTracking::AMBIENT:
            if (m_enableColorMaterial)
                getLighting().enableColorMaterial(false, true, false, false);
            break;
        case ColorMaterialTracking::DIFFUSE:
            if (m_enableColorMaterial)
                getLighting().enableColorMaterial(false, false, true, false);
            break;
        case ColorMaterialTracking::AMBIENT_AND_DIFFUSE:
            if (m_enableColorMaterial)
                getLighting().enableColorMaterial(false, true, true, false);
            break;
        case ColorMaterialTracking::SPECULAR:
            if (m_enableColorMaterial)
                getLighting().enableColorMaterial(false, false, false, true);
            break;
            case ColorMaterialTracking::EMISSION:
            if (m_enableColorMaterial)
                getLighting().enableColorMaterial(true, false, false, false);
            break;
        default:
            if (m_enableColorMaterial)
                getLighting().enableColorMaterial(false, true, true, false);
            break;
    }
    m_colorMaterialTracking = material;
    m_colorMaterialFace = face;
}

void VertexPipeline::enableColorMaterial(const bool enable)
{
    m_enableColorMaterial = enable;
    if (enable)
    {
        setColorMaterialTracking(m_colorMaterialFace, m_colorMaterialTracking);
    }
    else 
    {
        getLighting().enableColorMaterial(false, false, false, false);
    }
}
