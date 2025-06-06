// RasterIX
// https://github.com/ToNi3141/RasterIX
// Copyright (c) 2023 ToNi3141

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

#ifndef _FOG_COLOR_REG_
#define _FOG_COLOR_REG_

#include "renderer/registers/BaseColorReg.hpp"

namespace rr
{
class FogColorReg : public BaseColorReg
{
public:
    static constexpr uint32_t getAddr() { return 0x5; }
};
} // namespace rr

#endif // _FOG_COLOR_REG_
