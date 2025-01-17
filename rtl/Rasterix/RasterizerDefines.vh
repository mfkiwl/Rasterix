// Rasterix
// https://github.com/ToNi3141/Rasterix
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

localparam RASTERIZER_AXIS_VERTEX_ATTRIBUTE_SIZE = 32;
localparam RASTERIZER_AXIS_SCREEN_POS_SIZE = 16;

localparam RASTERIZER_AXIS_BOUNDING_BOX_POS_X_POS = 0;
localparam RASTERIZER_AXIS_BOUNDING_BOX_POS_Y_POS = RASTERIZER_AXIS_BOUNDING_BOX_POS_X_POS + RASTERIZER_AXIS_SCREEN_POS_SIZE;
localparam RASTERIZER_AXIS_SCREEN_POS_X_POS = RASTERIZER_AXIS_BOUNDING_BOX_POS_Y_POS + RASTERIZER_AXIS_SCREEN_POS_SIZE;
localparam RASTERIZER_AXIS_SCREEN_POS_Y_POS = RASTERIZER_AXIS_SCREEN_POS_X_POS + RASTERIZER_AXIS_SCREEN_POS_SIZE;
localparam RASTERIZER_AXIS_FRAMEBUFFER_INDEX_POS = RASTERIZER_AXIS_SCREEN_POS_Y_POS + RASTERIZER_AXIS_VERTEX_ATTRIBUTE_SIZE;

localparam RASTERIZER_AXIS_PARAMETER_SIZE = (1 * RASTERIZER_AXIS_VERTEX_ATTRIBUTE_SIZE) 
                            + (2 * RASTERIZER_AXIS_SCREEN_POS_SIZE)
                            + (2 * RASTERIZER_AXIS_SCREEN_POS_SIZE);
