#ifndef CLIPPER_HPP
#define CLIPPER_HPP

#include "Vec.hpp"
#include <tuple>
#include <array>
#include "IRenderer.hpp"

namespace rr
{

class Clipper 
{
public:
    // Each clipping plane can potentially introduce one more vertex. A triangle contains 3 vertexes, plus 6 possible planes, results in 9 vertexes
    using ClipTexCoords = std::array<Vec4, IRenderer::MAX_TMU_COUNT>;
    using ClipVertList = std::array<Vec4, 9>;
    using ClipTexCoordList = std::array<ClipTexCoords, 9>;

    static std::tuple<const uint32_t,
        ClipVertList &, 
        ClipTexCoordList &,
        ClipVertList &> clip(ClipVertList& vertList,
                             ClipVertList& vertListBuffer,
                             ClipTexCoordList& texCoordList,
                             ClipTexCoordList& texCoordListBuffer,
                             ClipVertList& colorList,
                             ClipVertList& colorListBuffer);

private:
    enum OutCode
    {
        OC_NONE    = 0x00,
        OC_NEAR    = 0x01,
        OC_FAR     = 0x02,
        OC_TOP     = 0x04,
        OC_BOTTOM  = 0x08,
        OC_LEFT    = 0x10,
        OC_RIGHT   = 0x20
    };

    static float lerpAmt(OutCode plane, const Vec4 &v0, const Vec4 &v1);
    static void lerpVert(Vec4& vOut, const Vec4& v0, const Vec4& v1, const float amt);
    static void lerpTexCoord(ClipTexCoords& vOut, const ClipTexCoords& v0, const ClipTexCoords& v1, const float amt);
    static OutCode outCode(const Vec4 &v);
    
    static uint32_t clipAgainstPlane(ClipVertList& vertListOut,
                                     ClipTexCoordList& texCoordListOut,
                                     ClipVertList& colorListOut,
                                     const OutCode clipPlane,
                                     const ClipVertList& vertListIn,
                                     const ClipTexCoordList& texCoordListIn,
                                     const ClipVertList& colorListIn,
                                     const uint32_t listInSize);

    friend Clipper::OutCode operator|=(Clipper::OutCode& lhs, Clipper::OutCode rhs);
};

Clipper::OutCode operator|=(Clipper::OutCode& lhs, Clipper::OutCode rhs);

} // namespace rr

#endif // CLIPPER_HPP
