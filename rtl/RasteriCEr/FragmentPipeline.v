// RasteriCEr
// https://github.com/ToNi3141/RasteriCEr
// Copyright (c) 2021 ToNi3141

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

module FragmentPipeline
#(
    // The minimum bit width which is required to contain the resolution
    parameter FRAMEBUFFER_INDEX_WIDTH = 14,
    localparam FLOAT_SIZE = 32
)
(
    input  wire        clk,
    input  wire        reset,
    output wire        pixelInPipeline,

    // Shader configurations
    input  wire [15:0] confReg1,
    input  wire [15:0] confReg2,
    input  wire [15:0] confTextureEnvColor,
    input  wire [15:0] triangleStaticColor,

    // Fragment Stream
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire [ATTR_INTERP_AXIS_PARAMETER_SIZE - 1 : 0] s_axis_tdata,

    // Texture access
    output reg  [31:0] texelIndex,
    input  wire [15:0] texel,

    // Frame buffer access
    // Read
    output reg  [FRAMEBUFFER_INDEX_WIDTH - 1 : 0] colorIndexRead,
    input  wire [15:0] colorIn,
    // Write
    output reg  [FRAMEBUFFER_INDEX_WIDTH - 1 : 0] colorIndexWrite,
    output reg         colorWriteEnable,
    output reg  [15:0] colorOut,

    // ZBuffer buffer access
    // Read
    output reg  [FRAMEBUFFER_INDEX_WIDTH - 1 : 0] depthIndexRead,
    input  wire [15:0] depthIn,
    // Write
    output reg  [FRAMEBUFFER_INDEX_WIDTH - 1 : 0] depthIndexWrite,
    output reg         depthWriteEnable,
    output reg  [15:0] depthOut
);
`include "RegisterAndDescriptorDefines.vh"
`include "AttributeInterpolatorDefines.vh"

    function [15:0] truncate16;
        input [31:0] in;
        begin
            truncate16 = in[0 +: 16];        
        end
    endfunction

    function [23:0] truncate24;
        input [31:0] in;
        begin
            truncate24 = in[0 +: 24];        
        end
    endfunction

    function [15:0] clampTexture;
        input [23:0] texCoord;
        input [ 0:0] mode; 
        begin
            clampTexture = texCoord[0 +: 16];
            if (mode == CLAMP_TO_EDGE)
            begin
                if (texCoord[23]) // Check if it lower than 0 by only checking the sign bit
                begin
                    clampTexture = 0;
                end
                else if ((texCoord >> 15) != 0) // Check if it is greater than one by checking if the integer part is unequal to zero
                begin
                    clampTexture = 16'h7fff;
                end  
            end
        end
    endfunction

    localparam SUB_PIXEL_WIDTH = COLOR_SUB_PIXEL_WIDTH;

    initial 
    begin
        if (SUB_PIXEL_WIDTH != 4)
        begin
            $error("Only sub pixel size of 4 is allowed");
        end
    end

    assign s_axis_tready = 1;

    reg [5:0] blendPixelState;
    reg [15:0] blenderTexFragCache;
    reg [15:0] blenderFbFragCache;
    reg blenderTransparencyDone;

    // Note st is a normalized number between 0.0 and 1.0. That means, every number befor the point is always
    // zero and can be cut off. Only the numbers after the point are from interest. So, we shift the n.23 number by 
    // 8 digits and reinterpet the 15 bits behind the point as normal integers do address the texel
    reg signed [15:0]  textureS; // textureSCorrected >> 8 (S7.23 >> 8 = S7.15 -> S0.15) (reinterpret as normal integer with the range 0..32767)
    reg signed [15:0]  textureT; // textureTCorrected >> 8 (S7.23 >> 8 = S7.15 -> S0.15) (reinterpret as normal integer with the range 0..32767)
    reg [FRAMEBUFFER_INDEX_WIDTH - 1 : 0] fbIndex;

    reg [15:0] newFbPixel;

    reg  [15:0] depthTestFragmentVal;
    reg  [15:0] depthTestDepthBufferVal;
    reg  depthTestPassed;
    wire depthTestLess = depthTestFragmentVal < depthTestDepthBufferVal;
    wire depthTestGreater = depthTestFragmentVal > depthTestDepthBufferVal;
    wire depthTestEqual = depthTestFragmentVal == depthTestDepthBufferVal;
    always @*
    begin
        case (confReg1[REG1_DEPTH_TEST_FUNC_POS +: REG1_DEPTH_TEST_FUNC_SIZE])
            ALWAYS:
                depthTestPassed = 1;
            NEVER:
                depthTestPassed = 0;
            LESS:
                depthTestPassed = depthTestLess;
            EQUAL:
                depthTestPassed = depthTestEqual;
            LEQUAL:
                depthTestPassed = depthTestLess | depthTestEqual;
            GREATER:
                depthTestPassed = depthTestGreater;
            NOTEQUAL:
                depthTestPassed = !depthTestEqual;
            GEQUAL:
                depthTestPassed = depthTestGreater | depthTestEqual;
            default: 
                depthTestPassed = 1;
        endcase
    end

    reg  [ 3:0] alphaTestFragmentVal;
    reg         alphaTestPassed;
    wire [ 3:0] alphaTestRefVal = confReg1[REG1_ALPHA_TEST_REF_VALUE_POS +: REG1_ALPHA_TEST_REF_VALUE_SIZE];
    wire        alphaTestLess = alphaTestFragmentVal < alphaTestRefVal;
    wire        alphaTestGreater = alphaTestFragmentVal > alphaTestRefVal;
    wire        alphaTestEqual = alphaTestFragmentVal == alphaTestRefVal;
    always @*
    begin
        case (confReg1[REG1_ALPHA_TEST_FUNC_POS +: REG1_ALPHA_TEST_FUNC_SIZE])
            ALWAYS:
                alphaTestPassed = 1;
            NEVER:
                alphaTestPassed = 0;
            LESS:
                alphaTestPassed = alphaTestLess;
            EQUAL:
                alphaTestPassed = alphaTestEqual;
            LEQUAL:
                alphaTestPassed = alphaTestLess | alphaTestEqual;
            GREATER:
                alphaTestPassed = alphaTestGreater;
            NOTEQUAL:
                alphaTestPassed = !alphaTestEqual;
            GEQUAL:
                alphaTestPassed = alphaTestGreater | alphaTestEqual;
            default: 
                alphaTestPassed = 1;
        endcase
    end
    
    localparam BLENDPIXEL_WAIT_FOR_REQUEST = 0;
    localparam BLENDPIXEL_CALCULATE_PERSPECTIVE_CORRECTION = 1;
    localparam BLENDPIXEL_REQUEST_FB = 2;
    localparam BLENDPIXEL_BLEND_PIXEL = 3;
    localparam BLENDPIXEL_SAVE_FB = 4;
    localparam BLENDPIXEL_EXECUTE = 5;

    ValueTrack pixelTracker (
        .aclk(clk),
        .resetn(!reset),
        
        .sigIncommingValue(s_axis_tvalid & s_axis_tready),
        .sigOutgoingValue(stepWriteBackValid),
        .valueInPipeline(pixelInPipeline)
    );

    ////////////////////////////////////////////////////////////////////////////
    // STEP Convert to int
    ////////////////////////////////////////////////////////////////////////////
    wire [ATTR_INTERP_AXIS_VERTEX_ATTRIBUTE_SIZE - 1 : 0]  step_convert_framebuffer_index;
    wire [ATTR_INTERP_AXIS_VERTEX_ATTRIBUTE_SIZE - 1 : 0]  step_convert_depth_w;
    wire [31 : 0]                   step_convert_texture_s;
    wire [31 : 0]                   step_convert_texture_t;
    wire                            step_convert_tvalid;
    wire [31 : 0]                   step_convert_w;

    ValueDelay #(.VALUE_SIZE(ATTR_INTERP_AXIS_VERTEX_ATTRIBUTE_SIZE), .DELAY(4)) 
        convert_framebuffer_delay (.clk(clk), .in(s_axis_tdata[ATTR_INTERP_AXIS_FRAMEBUFFER_INDEX_POS +: ATTR_INTERP_AXIS_VERTEX_ATTRIBUTE_SIZE]), .out(step_convert_framebuffer_index));
    ValueDelay #(.VALUE_SIZE(ATTR_INTERP_AXIS_VERTEX_ATTRIBUTE_SIZE), .DELAY(4)) 
        convert_depth_delay (.clk(clk), .in(s_axis_tdata[ATTR_INTERP_AXIS_INC_DEPTH_W_POS +: ATTR_INTERP_AXIS_VERTEX_ATTRIBUTE_SIZE]), .out(step_convert_depth_w));
    ValueDelay #(.VALUE_SIZE(1), .DELAY(4)) 
        convert_valid_delay (.clk(clk), .in(s_axis_tvalid), .out(step_convert_tvalid));

    FloatToInt #(.MANTISSA_SIZE(FLOAT_SIZE - 9), .EXPONENT_SIZE(8), .INT_SIZE(32), .EXPONENT_BIAS_OFFSET(-15))
        convert_floatToInt_TextureS (.clk(clk), .in(s_axis_tdata[ATTR_INTERP_AXIS_INC_TEXTURE_S_POS + (ATTR_INTERP_AXIS_VERTEX_ATTRIBUTE_SIZE - FLOAT_SIZE)+: FLOAT_SIZE]), .out(step_convert_texture_s));
    FloatToInt #(.MANTISSA_SIZE(FLOAT_SIZE - 9), .EXPONENT_SIZE(8), .INT_SIZE(32), .EXPONENT_BIAS_OFFSET(-15))
        convert_floatToInt_TextureT (.clk(clk), .in(s_axis_tdata[ATTR_INTERP_AXIS_INC_TEXTURE_T_POS + (ATTR_INTERP_AXIS_VERTEX_ATTRIBUTE_SIZE - FLOAT_SIZE) +: FLOAT_SIZE]), .out(step_convert_texture_t));   
    FloatToInt #(.MANTISSA_SIZE(FLOAT_SIZE - 9), .EXPONENT_SIZE(8), .INT_SIZE(32), .EXPONENT_BIAS_OFFSET(-7))
        convert_floatToInt_DepthW (.clk(clk), .in(s_axis_tdata[ATTR_INTERP_AXIS_INC_DEPTH_W_POS + (ATTR_INTERP_AXIS_VERTEX_ATTRIBUTE_SIZE - FLOAT_SIZE) +: FLOAT_SIZE]), .out(step_convert_w));   

    reg                         stepCalculatePerspectiveCorrectionValid = 0;
    reg [15:0]                  stepCalculatePerspectiveCorrectionDepthBufferVal = 0;
    reg [FRAMEBUFFER_INDEX_WIDTH - 1 : 0] stepCalculatePerspectiveCorrectionfbIndex = 0;
    reg [ATTR_INTERP_AXIS_VERTEX_ATTRIBUTE_SIZE - 1 : 0]   stepCalculatePerspectiveCorrectionTriangleColor = 0;
    always @(posedge clk)
    begin
        // reg [31:0] z;
        // reg [63:0] double;
        // z = step_convert_depth_w;
        // double = {z[31], z[30], {3{~z[30]}}, z[29:23], z[22:0], {29{1'b0}}};
        // $display("valid %d d %f 0x%x", step_convert_tvalid, $bitstoreal(double), step_convert_depth_w);

        if (step_convert_tvalid)
        begin
            textureS = clampTexture(step_convert_texture_s[0 +: 24], confReg2[REG2_TEX_CLAMP_S_POS +: REG2_TEX_CLAMP_S_SIZE]);
            textureT = clampTexture(step_convert_texture_t[0 +: 24], confReg2[REG2_TEX_CLAMP_T_POS +: REG2_TEX_CLAMP_T_SIZE]);
            // TODO: Use the float value from step_convert_depth_w[(FLOAT_SIZE - 1) - 16 +: 16];
            // Currently this does not work. I dont know why the depth buffer does not work when using the float
            stepCalculatePerspectiveCorrectionDepthBufferVal <= step_convert_w[0 +: 16]; 
            stepCalculatePerspectiveCorrectionfbIndex <= step_convert_framebuffer_index[0 +: FRAMEBUFFER_INDEX_WIDTH];
            colorIndexRead <= step_convert_framebuffer_index[0 +: FRAMEBUFFER_INDEX_WIDTH];
            depthIndexRead <= step_convert_framebuffer_index[0 +: FRAMEBUFFER_INDEX_WIDTH];
            texelIndex <= {textureT, textureS};
        end
        stepCalculatePerspectiveCorrectionTriangleColor <= {16'h0, triangleStaticColor};
        stepCalculatePerspectiveCorrectionValid <= step_convert_tvalid;

    end

    reg                         stepWaitForMemoryValid = 0;
    reg [FRAMEBUFFER_INDEX_WIDTH - 1 : 0] stepWaitForMemoryFbIndex = 0;
    reg [15:0]                  stepWaitForMemoryDepthValue = 0;    
    reg [ATTR_INTERP_AXIS_VERTEX_ATTRIBUTE_SIZE - 1 : 0]   stepWaitForMemoryTriangleColor = 0;
    always @(posedge clk)
    begin
        if (stepCalculatePerspectiveCorrectionValid)
        begin
            stepWaitForMemoryFbIndex <= stepCalculatePerspectiveCorrectionfbIndex;
            stepWaitForMemoryDepthValue <= stepCalculatePerspectiveCorrectionDepthBufferVal;
        end
        stepWaitForMemoryTriangleColor <= stepCalculatePerspectiveCorrectionTriangleColor;
        stepWaitForMemoryValid <= stepCalculatePerspectiveCorrectionValid;
    end

    // TexEnv
    reg                         stepTexEnvValid = 0;
    reg [FRAMEBUFFER_INDEX_WIDTH - 1 : 0] stepTexEnvFbIndex = 0;
    reg [15:0]                  stepTexEnvColorFrag = 0;
    reg [15:0]                  stepTexEnvDepthValue = 0;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepTexEnvV00;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepTexEnvV01;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepTexEnvV02;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepTexEnvV03;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepTexEnvV10;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepTexEnvV11;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepTexEnvV12;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepTexEnvV13;
    always @(posedge clk)
    begin : TexEnvCalc
        reg [SUB_PIXEL_WIDTH - 1 : 0] rs;
        reg [SUB_PIXEL_WIDTH - 1 : 0] gs;
        reg [SUB_PIXEL_WIDTH - 1 : 0] bs;
        reg [SUB_PIXEL_WIDTH - 1 : 0] as;
        reg [SUB_PIXEL_WIDTH - 1 : 0] rp;
        reg [SUB_PIXEL_WIDTH - 1 : 0] gp;
        reg [SUB_PIXEL_WIDTH - 1 : 0] bp;
        reg [SUB_PIXEL_WIDTH - 1 : 0] ap;
        reg [SUB_PIXEL_WIDTH - 1 : 0] rc;
        reg [SUB_PIXEL_WIDTH - 1 : 0] gc;
        reg [SUB_PIXEL_WIDTH - 1 : 0] bc;
        reg [SUB_PIXEL_WIDTH - 1 : 0] ac;

        reg [SUB_PIXEL_WIDTH - 1 : 0] v00;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v01;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v02;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v03;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v10;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v11;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v12;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v13;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v20;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v21;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v22;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v23;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v30;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v31;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v32;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v33;

        // Texture source color (Cs)
        rs = texel[COLOR_R_POS +: SUB_PIXEL_WIDTH];
        gs = texel[COLOR_G_POS +: SUB_PIXEL_WIDTH];
        bs = texel[COLOR_B_POS +: SUB_PIXEL_WIDTH];
        as = texel[COLOR_A_POS +: SUB_PIXEL_WIDTH];

        // Input of texture unit n (or in case of texture unit 0 it is the primary color of the triangle (Cf))
        // Currently we only have one texture unit, so Cp is Cf
        rp = stepWaitForMemoryTriangleColor[COLOR_R_POS +: SUB_PIXEL_WIDTH];
        gp = stepWaitForMemoryTriangleColor[COLOR_G_POS +: SUB_PIXEL_WIDTH];
        bp = stepWaitForMemoryTriangleColor[COLOR_B_POS +: SUB_PIXEL_WIDTH];
        ap = stepWaitForMemoryTriangleColor[COLOR_A_POS +: SUB_PIXEL_WIDTH];

        // Texture environment color (Cc)
        rc = confTextureEnvColor[COLOR_R_POS +: SUB_PIXEL_WIDTH];
        gc = confTextureEnvColor[COLOR_G_POS +: SUB_PIXEL_WIDTH];
        bc = confTextureEnvColor[COLOR_B_POS +: SUB_PIXEL_WIDTH];
        ac = confTextureEnvColor[COLOR_A_POS +: SUB_PIXEL_WIDTH];

        case (confReg2[REG2_TEX_ENV_FUNC_POS +: REG2_TEX_ENV_FUNC_SIZE])
            DISABLE:
            begin
                // Disables the tex env, so just use the triangle color instread of the texture
                // (The opposite of the GL_REPLACE)

                v00 = rp;
                v01 = gp;
                v02 = bp;
                v03 = ap;

                v10 = 4'hf;
                v11 = 4'hf;
                v12 = 4'hf;
                v13 = 4'hf;

                v20 = 0;
                v21 = 0;
                v22 = 0;
                v23 = 0;

                v30 = 0;
                v31 = 0;
                v32 = 0;
                v33 = 0;
            end
            REPLACE:
            begin
                // (s * 1.0) + (0.0 * 0.0)
                // (as * 1.0) + (0.0 * 0.0)

                v00 = rs;
                v01 = gs;
                v02 = bs;
                v03 = as;

                v10 = 4'hf;
                v11 = 4'hf;
                v12 = 4'hf;
                v13 = 4'hf;

                v20 = 0;
                v21 = 0;
                v22 = 0;
                v23 = 0;

                v30 = 0;
                v31 = 0;
                v32 = 0;
                v33 = 0;
            end
            BLEND:
            begin
                // (p * (1.0 - s) + (c * s)
                // (ap * as) + (0.0 * 0.0)      
                
                v00 = rp;
                v01 = gp;
                v02 = bp;
                v03 = ap;

                v10 = 4'hf - rs;
                v11 = 4'hf - gs;
                v12 = 4'hf - bs;
                v13 = as;

                v20 = rc;
                v21 = gc;
                v22 = bc;
                v23 = 0;

                v30 = rs;
                v31 = gs;
                v32 = bs;
                v33 = 0; 
            end 
            DECAL:
            begin
                // (p * (1.0 - as)) + (s * as)
                // (ap * 1.0) + (0.0 * 0.0)

                v00 = rp;
                v01 = gp;
                v02 = bp;
                v03 = ap;

                v10 = (4'hf - as);
                v11 = (4'hf - as);
                v12 = (4'hf - as);
                v13 = 4'hf;
                
                v20 = rs;
                v21 = gs;
                v22 = bs;
                v23 = 0;

                v30 = as;
                v31 = as;
                v32 = as;
                v33 = 0;
                
            end
            MODULATE:
            begin
                // (p * s) + (0 * 0)
                // (ap * as) + (0.0 * 0.0)

                v00 = rp;
                v01 = gp;
                v02 = bp;
                v03 = ap;

                v10 = rs;
                v11 = gs;
                v12 = bs;
                v13 = as;

                v20 = 0;
                v21 = 0;
                v22 = 0;
                v23 = 0;

                v30 = 0;
                v31 = 0;
                v32 = 0;
                v33 = 0;
            end
            ADD:
            begin 
                // (p * 1.0) + (s * 1.0)
                // (ap * as) + (0.0 * 0.0)

                v00 = rp;
                v01 = gp;
                v02 = bp;
                v03 = ap;

                v10 = 4'hf;
                v11 = 4'hf;
                v12 = 4'hf;
                v13 = as;

                v20 = rs;
                v21 = gs;
                v22 = bs;
                v23 = 0;

                v30 = 4'hf;
                v31 = 4'hf;
                v32 = 4'hf;
                v33 = 0;
            end
            default:
            begin
                
            end 
        endcase

        stepTexEnvV00 <= v00 * v10;
        stepTexEnvV01 <= v01 * v11;
        stepTexEnvV02 <= v02 * v12;
        stepTexEnvV03 <= v03 * v13;

        stepTexEnvV10 <= v20 * v30;
        stepTexEnvV11 <= v21 * v31;
        stepTexEnvV12 <= v22 * v32;
        stepTexEnvV13 <= v23 * v33;

        stepTexEnvValid <= stepWaitForMemoryValid;
        stepTexEnvFbIndex <= stepWaitForMemoryFbIndex;
        stepTexEnvDepthValue <= stepWaitForMemoryDepthValue;
        stepTexEnvColorFrag <= colorIn;

        // Execute early z test. Advantage: We then just have to remember the bit of the result if the z test instead of 
        // the depth value from the depth buffer.
        depthTestDepthBufferVal <= depthIn;
        depthTestFragmentVal <= stepWaitForMemoryDepthValue;
    end

    // Tex Env Result
    reg                         stepTexEnvResultValid = 0;
    reg [FRAMEBUFFER_INDEX_WIDTH - 1 : 0] stepTexEnvResultFbIndex = 0;
    reg [15:0]                  stepTexEnvResultColorFrag = 0;
    reg [15:0]                  stepTexEnvResultColorTex = 0;
    reg [15:0]                  stepTexEnvResultDepthValue = 0;
    reg                         stepTexEnvResultWriteColor = 0;
    always @(posedge clk)
    begin : TexEnvResultCalc
        reg [(SUB_PIXEL_WIDTH * 2) : 0] r;
        reg [(SUB_PIXEL_WIDTH * 2) : 0] g;
        reg [(SUB_PIXEL_WIDTH * 2) : 0] b;
        reg [(SUB_PIXEL_WIDTH * 2) : 0] a;

        r = (stepTexEnvV00 + stepTexEnvV10) + 8'hf;
        g = (stepTexEnvV01 + stepTexEnvV11) + 8'hf;
        b = (stepTexEnvV02 + stepTexEnvV12) + 8'hf;
        a = (stepTexEnvV03 + stepTexEnvV13) + 8'hf;

        stepTexEnvResultColorTex <= {
            // Saturate colors 
            (r[8]) ? 4'hf : r[7:4],
            (g[8]) ? 4'hf : g[7:4],
            (b[8]) ? 4'hf : b[7:4],
            (a[8]) ? 4'hf : a[7:4]
        };

        stepTexEnvResultDepthValue <= stepTexEnvDepthValue;
        stepTexEnvResultColorFrag <= stepTexEnvColorFrag;
        stepTexEnvResultFbIndex <= stepTexEnvFbIndex;
        stepTexEnvResultValid <= stepTexEnvValid;
        // Check if the depth test passed or force to always pass the depth test when the depth test is disabled
        stepTexEnvResultWriteColor <= depthTestPassed || !confReg1[REG1_ENABLE_DEPTH_TEST_POS +: REG1_ENABLE_DEPTH_TEST_SIZE];
        alphaTestFragmentVal <= (a[8]) ? 4'hf : a[7:4];
    end

    // Blend color
    reg                         stepBlendValid = 0;
    reg [FRAMEBUFFER_INDEX_WIDTH - 1 : 0] stepBlendFbIndex = 0;
    reg [15:0]                  stepBlendDepthValue = 0;
    reg                         stepBlendWriteColor = 0;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepBlendV00;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepBlendV01;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepBlendV02;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepBlendV03;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepBlendV10;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepBlendV11;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepBlendV12;
    reg [(SUB_PIXEL_WIDTH * 2) - 1 : 0] stepBlendV13;
    always @(posedge clk)
    begin : BlendCalc
        reg [SUB_PIXEL_WIDTH - 1 : 0] rs;
        reg [SUB_PIXEL_WIDTH - 1 : 0] gs;
        reg [SUB_PIXEL_WIDTH - 1 : 0] bs;
        reg [SUB_PIXEL_WIDTH - 1 : 0] as;
        reg [SUB_PIXEL_WIDTH - 1 : 0] rd;
        reg [SUB_PIXEL_WIDTH - 1 : 0] gd;
        reg [SUB_PIXEL_WIDTH - 1 : 0] bd;
        reg [SUB_PIXEL_WIDTH - 1 : 0] ad;

        reg [SUB_PIXEL_WIDTH - 1 : 0] v00;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v01;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v02;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v03;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v10;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v11;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v12;
        reg [SUB_PIXEL_WIDTH - 1 : 0] v13;

        rs = stepTexEnvResultColorTex[COLOR_R_POS +: SUB_PIXEL_WIDTH];
        gs = stepTexEnvResultColorTex[COLOR_G_POS +: SUB_PIXEL_WIDTH];
        bs = stepTexEnvResultColorTex[COLOR_B_POS +: SUB_PIXEL_WIDTH];
        as = stepTexEnvResultColorTex[COLOR_A_POS +: SUB_PIXEL_WIDTH];

        rd = stepTexEnvResultColorFrag[COLOR_R_POS +: SUB_PIXEL_WIDTH];
        gd = stepTexEnvResultColorFrag[COLOR_G_POS +: SUB_PIXEL_WIDTH];
        bd = stepTexEnvResultColorFrag[COLOR_B_POS +: SUB_PIXEL_WIDTH];
        ad = stepTexEnvResultColorFrag[COLOR_A_POS +: SUB_PIXEL_WIDTH];

        case (confReg2[REG2_BLEND_FUNC_SFACTOR_POS +: REG2_BLEND_FUNC_SFACTOR_SIZE])
            ZERO:
            begin
                v00 = 4'h0;
                v01 = 4'h0;
                v02 = 4'h0;
                v03 = 4'h0;
            end
            ONE:
            begin
                v00 = 4'hf;
                v01 = 4'hf;
                v02 = 4'hf;
                v03 = 4'hf;
            end 
            DST_COLOR:
            begin
                v00 = rd;
                v01 = gd;
                v02 = bd;
                v03 = ad;
            end 
            ONE_MINUS_DST_COLOR:
            begin
                v00 = 4'hf - rd;
                v01 = 4'hf - gd;
                v02 = 4'hf - bd;
                v03 = 4'hf - ad;
            end 
            SRC_ALPHA:
            begin
                v00 = as;
                v01 = as;
                v02 = as;
                v03 = as;
            end 
            ONE_MINUS_SRC_ALPHA:
            begin
                v00 = 4'hf - as;
                v01 = 4'hf - as;
                v02 = 4'hf - as;
                v03 = 4'hf - as;
            end 
            DST_ALPHA:
            begin
                v00 = ad;
                v01 = ad;
                v02 = ad;
                v03 = ad;
            end 
            ONE_MINUS_DST_ALPHA:
            begin
                v00 = 4'hf - ad;
                v01 = 4'hf - ad;
                v02 = 4'hf - ad;
                v03 = 4'hf - ad;
            end 
            SRC_ALPHA_SATURATE:
            begin
                v00 = (as < (4'hf - ad)) ? as : (4'hf - ad);
                v01 = (as < (4'hf - ad)) ? as : (4'hf - ad);
                v02 = (as < (4'hf - ad)) ? as : (4'hf - ad);
                v03 = 4'hf;
            end 
            default:
            begin
                
            end 
        endcase

        case (confReg2[REG2_BLEND_FUNC_DFACTOR_POS +: REG2_BLEND_FUNC_DFACTOR_SIZE])
            ZERO:
            begin
                v10 = 4'h0;
                v11 = 4'h0;
                v12 = 4'h0;
                v13 = 4'h0;
            end
            ONE:
            begin
                v10 = 4'hf;
                v11 = 4'hf;
                v12 = 4'hf;
                v13 = 4'hf;
            end 
            SRC_COLOR:
            begin
                v10 = rs;
                v11 = gs;
                v12 = bs;
                v13 = as;
            end 
            ONE_MINUS_SRC_COLOR:
            begin
                v10 = 4'hf - rs;
                v11 = 4'hf - gs;
                v12 = 4'hf - bs;
                v13 = 4'hf - as;
            end 
            SRC_ALPHA:
            begin
                v10 = as;
                v11 = as;
                v12 = as;
                v13 = as;
            end 
            ONE_MINUS_SRC_ALPHA:
            begin
                v10 = 4'hf - as;
                v11 = 4'hf - as;
                v12 = 4'hf - as;
                v13 = 4'hf - as;
            end 
            DST_ALPHA:
            begin
                v10 = ad;
                v11 = ad;
                v12 = ad;
                v13 = ad;
            end 
            ONE_MINUS_DST_ALPHA:
            begin
                v10 = 4'hf - ad;
                v11 = 4'hf - ad;
                v12 = 4'hf - ad;
                v13 = 4'hf - ad;
            end 
            default:
            begin
                
            end 
        endcase

        stepBlendV00 <= v00 * rs;
        stepBlendV01 <= v01 * gs;
        stepBlendV02 <= v02 * bs;
        stepBlendV03 <= v03 * as;
    
        stepBlendV10 <= v10 * rd;
        stepBlendV11 <= v11 * gd;
        stepBlendV12 <= v12 * bd;
        stepBlendV13 <= v13 * ad;
        
        stepBlendDepthValue <= stepTexEnvResultDepthValue;
        stepBlendFbIndex <= stepTexEnvResultFbIndex;
        stepBlendValid <= stepTexEnvResultValid;
        stepBlendWriteColor <= stepTexEnvResultWriteColor & alphaTestPassed;
    end

    // Blend Result
    reg                         stepBlendResultValid = 0;
    reg [FRAMEBUFFER_INDEX_WIDTH - 1 : 0] stepBlendResultFbIndex = 0;
    reg [15:0]                  stepBlendResultColorFrag = 0;
    reg [15:0]                  stepBlendResultDepthValue = 0;
    reg                         stepBlendResultWriteColor = 0;
    always @(posedge clk)
    begin : BlendResultCalc
        reg [(SUB_PIXEL_WIDTH * 2) : 0] r;
        reg [(SUB_PIXEL_WIDTH * 2) : 0] g;
        reg [(SUB_PIXEL_WIDTH * 2) : 0] b;
        reg [(SUB_PIXEL_WIDTH * 2) : 0] a;

        r = (stepBlendV00 + stepBlendV10) + 8'hf;
        g = (stepBlendV01 + stepBlendV11) + 8'hf;
        b = (stepBlendV02 + stepBlendV12) + 8'hf;
        a = (stepBlendV03 + stepBlendV13) + 8'hf;

        stepBlendResultColorFrag <= {
            // Saturate colors 
            (r[8]) ? 4'hf : r[7:4], 
            (g[8]) ? 4'hf : g[7:4], 
            (b[8]) ? 4'hf : b[7:4],
            (a[8]) ? 4'hf : a[7:4]
        };

        stepBlendResultDepthValue <= stepBlendDepthValue;
        stepBlendResultFbIndex <= stepBlendFbIndex;
        stepBlendResultValid <= stepBlendValid;
        stepBlendResultWriteColor <= stepBlendWriteColor;
    end

    // Bubble (introduces a bubble cycle (see FragmentPipelineIce40Wrapper))
    reg                         stepBubbleValid = 0;
    reg [FRAMEBUFFER_INDEX_WIDTH - 1 : 0] stepBubbleFbIndex = 0;
    reg [15:0]                  stepBubbleColorFrag = 0;
    reg [15:0]                  stepBubbleDepthValue = 0;
    reg                         stepBubbleWriteColor = 0;
    always @(posedge clk)
    begin
        stepBubbleDepthValue <= stepBlendResultDepthValue;
        stepBubbleColorFrag <= stepBlendResultColorFrag;
        stepBubbleFbIndex <= stepBlendResultFbIndex;
        stepBubbleValid <= stepBlendResultValid;
        stepBubbleWriteColor <= stepBlendResultWriteColor;
    end

    // Write back
    reg stepWriteBackValid = 0;
    always @(posedge clk)
    begin
        if (stepBubbleValid)
        begin
            colorIndexWrite <= stepBubbleFbIndex;
            depthIndexWrite <= stepBubbleFbIndex;
            depthOut <= stepBubbleDepthValue;
            colorOut <= stepBubbleColorFrag;
        end
        stepWriteBackValid <= stepBubbleValid;
        colorWriteEnable <= stepBubbleValid & stepBubbleWriteColor;
        depthWriteEnable <= stepBubbleValid & stepBubbleWriteColor & confReg1[REG1_ENABLE_DEPTH_TEST_POS +: REG1_ENABLE_DEPTH_TEST_SIZE];
    end
endmodule