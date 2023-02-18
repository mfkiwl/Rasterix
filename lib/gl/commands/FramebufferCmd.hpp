#ifndef _FRAMEBUFFER_CMD_HPP_
#define _FRAMEBUFFER_CMD_HPP_

#include <cstdint>
#include <array>
#include <tcb/span.hpp>
#include "DmaStreamEngineCommands.hpp"

namespace rr
{

class FramebufferCmd
{
    static constexpr uint32_t OP_FRAMEBUFFER { 0x2000'0000 };
    static constexpr uint32_t OP_FRAMEBUFFER_COMMIT { OP_FRAMEBUFFER | 0x0000'0001 };
    static constexpr uint32_t OP_FRAMEBUFFER_MEMSET { OP_FRAMEBUFFER | 0x0000'0002 };
    static constexpr uint32_t OP_FRAMEBUFFER_COLOR_BUFFER_SELECT { OP_FRAMEBUFFER | 0x0000'0010 };
    static constexpr uint32_t OP_FRAMEBUFFER_DEPTH_BUFFER_SELECT { OP_FRAMEBUFFER | 0x0000'0020 };
    using DseTransferType = std::array<DSEC::Transfer, 1>;
public:
    FramebufferCmd(const bool selColorBuffer, const bool selDepthBuffer)
    {
        if (selColorBuffer)
        {
            selectColorBuffer();
        }
        if (selDepthBuffer)
        {
            selectDepthBuffer();
        }
    }

    void enableCommit(const uint32_t size, const uint32_t addr, const bool commitToStream) 
    { 
        m_op |= OP_FRAMEBUFFER_COMMIT; 
        if (commitToStream)
        {
            m_dseOp = DSEC::OP_COMMIT_TO_STREAM;
        }
        else
        {
            m_dseOp = DSEC::OP_COMMIT_TO_MEMORY;
        }
        m_dseData = { { addr, size } };

    }
    void enableMemset() 
    { 
        m_op |= OP_FRAMEBUFFER_MEMSET;
        m_dseOp = DSEC::OP_NOP;
    }
    void selectColorBuffer() { m_op |= OP_FRAMEBUFFER_COLOR_BUFFER_SELECT; }
    void selectDepthBuffer() { m_op |= OP_FRAMEBUFFER_DEPTH_BUFFER_SELECT; }

    using Desc = std::array<tcb::span<uint8_t>, 0>;
    void serialize(Desc&) const {}
    uint32_t command() const { return m_op; }

    DSEC::SCT dseOp() const { return m_dseOp; }
    const DseTransferType& dseTransfer() const { return m_dseData; }

private:
    uint32_t m_op {};
    DSEC::SCT m_dseOp { DSEC::OP_NOP };
    DseTransferType m_dseData {};
};

} // namespace rr

#endif // _FRAMEBUFFER_CMD_HPP_
