//-----------------------------------------------------------------
//                      DVI / HDMI Framebuffer
//                              V0.1
//                     github.com/ultraembedded
//                          Copyright 2020
//
//                 Email: admin@ultra-embedded.com
//
//                       License: MIT
//-----------------------------------------------------------------
// Copyright (c) 2020 github.com/ultraembedded
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//-----------------------------------------------------------------

`include "dvi_framebuffer_defs.v"

//-----------------------------------------------------------------
// Module:  DVI Framebuffer
//-----------------------------------------------------------------
module dvi_framebuffer
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter VIDEO_WIDTH      = 800
    ,parameter VIDEO_HEIGHT     = 600
    ,parameter VIDEO_REFRESH    = 72
    ,parameter VIDEO_ENABLE     = 1
    ,parameter VIDEO_X2_MODE    = 0
    ,parameter VIDEO_FB_RAM     = 32'h3000000
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input          clk_i
    ,input          rst_i
    ,input          clk_x5_i
    ,input          cfg_awvalid_i
    ,input  [31:0]  cfg_awaddr_i
    ,input          cfg_wvalid_i
    ,input  [31:0]  cfg_wdata_i
    ,input  [3:0]   cfg_wstrb_i
    ,input          cfg_bready_i
    ,input          cfg_arvalid_i
    ,input  [31:0]  cfg_araddr_i
    ,input          cfg_rready_i
    ,input          outport_awready_i
    ,input          outport_wready_i
    ,input          outport_bvalid_i
    ,input  [1:0]   outport_bresp_i
    ,input  [3:0]   outport_bid_i
    ,input          outport_arready_i
    ,input          outport_rvalid_i
    ,input  [31:0]  outport_rdata_i
    ,input  [1:0]   outport_rresp_i
    ,input  [3:0]   outport_rid_i
    ,input          outport_rlast_i

    // Outputs
    ,output         cfg_awready_o
    ,output         cfg_wready_o
    ,output         cfg_bvalid_o
    ,output [1:0]   cfg_bresp_o
    ,output         cfg_arready_o
    ,output         cfg_rvalid_o
    ,output [31:0]  cfg_rdata_o
    ,output [1:0]   cfg_rresp_o
    ,output         intr_o
    ,output         outport_awvalid_o
    ,output [31:0]  outport_awaddr_o
    ,output [3:0]   outport_awid_o
    ,output [7:0]   outport_awlen_o
    ,output [1:0]   outport_awburst_o
    ,output         outport_wvalid_o
    ,output [31:0]  outport_wdata_o
    ,output [3:0]   outport_wstrb_o
    ,output         outport_wlast_o
    ,output         outport_bready_o
    ,output         outport_arvalid_o
    ,output [31:0]  outport_araddr_o
    ,output [3:0]   outport_arid_o
    ,output [7:0]   outport_arlen_o
    ,output [1:0]   outport_arburst_o
    ,output         outport_rready_o
    ,output         dvi_red_o
    ,output         dvi_green_o
    ,output         dvi_blue_o
    ,output         dvi_clock_o
);

//-----------------------------------------------------------------
// Write address / data split
//-----------------------------------------------------------------
// Address but no data ready
reg awvalid_q;

// Data but no data ready
reg wvalid_q;

wire wr_cmd_accepted_w  = (cfg_awvalid_i && cfg_awready_o) || awvalid_q;
wire wr_data_accepted_w = (cfg_wvalid_i  && cfg_wready_o)  || wvalid_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    awvalid_q <= 1'b0;
else if (cfg_awvalid_i && cfg_awready_o && !wr_data_accepted_w)
    awvalid_q <= 1'b1;
else if (wr_data_accepted_w)
    awvalid_q <= 1'b0;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    wvalid_q <= 1'b0;
else if (cfg_wvalid_i && cfg_wready_o && !wr_cmd_accepted_w)
    wvalid_q <= 1'b1;
else if (wr_cmd_accepted_w)
    wvalid_q <= 1'b0;

//-----------------------------------------------------------------
// Capture address (for delayed data)
//-----------------------------------------------------------------
reg [7:0] wr_addr_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    wr_addr_q <= 8'b0;
else if (cfg_awvalid_i && cfg_awready_o)
    wr_addr_q <= cfg_awaddr_i[7:0];

wire [7:0] wr_addr_w = awvalid_q ? wr_addr_q : cfg_awaddr_i[7:0];

//-----------------------------------------------------------------
// Retime write data
//-----------------------------------------------------------------
reg [31:0] wr_data_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    wr_data_q <= 32'b0;
else if (cfg_wvalid_i && cfg_wready_o)
    wr_data_q <= cfg_wdata_i;

//-----------------------------------------------------------------
// Request Logic
//-----------------------------------------------------------------
wire read_en_w  = cfg_arvalid_i & cfg_arready_o;
wire write_en_w = wr_cmd_accepted_w && wr_data_accepted_w;

//-----------------------------------------------------------------
// Accept Logic
//-----------------------------------------------------------------
assign cfg_arready_o = ~cfg_rvalid_o;
assign cfg_awready_o = ~cfg_bvalid_o && ~cfg_arvalid_i && ~awvalid_q;
assign cfg_wready_o  = ~cfg_bvalid_o && ~cfg_arvalid_i && ~wvalid_q;


//-----------------------------------------------------------------
// Register config
//-----------------------------------------------------------------
reg config_wr_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    config_wr_q <= 1'b0;
else if (write_en_w && (wr_addr_w[7:0] == `CONFIG))
    config_wr_q <= 1'b1;
else
    config_wr_q <= 1'b0;

// config_x2_mode [internal]
reg        config_x2_mode_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    config_x2_mode_q <= VIDEO_X2_MODE;
else if (write_en_w && (wr_addr_w[7:0] == `CONFIG))
    config_x2_mode_q <= cfg_wdata_i[`CONFIG_X2_MODE_R];

wire        config_x2_mode_out_w = config_x2_mode_q;


// config_int_en_sof [internal]
reg        config_int_en_sof_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    config_int_en_sof_q <= 1'd`CONFIG_INT_EN_SOF_DEFAULT;
else if (write_en_w && (wr_addr_w[7:0] == `CONFIG))
    config_int_en_sof_q <= cfg_wdata_i[`CONFIG_INT_EN_SOF_R];

wire        config_int_en_sof_out_w = config_int_en_sof_q;


// config_enable [internal]
reg        config_enable_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    config_enable_q <= VIDEO_ENABLE;
else if (write_en_w && (wr_addr_w[7:0] == `CONFIG))
    config_enable_q <= cfg_wdata_i[`CONFIG_ENABLE_R];

wire        config_enable_out_w = config_enable_q;

//-----------------------------------------------------------------
// Register status
//-----------------------------------------------------------------
reg status_wr_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    status_wr_q <= 1'b0;
else if (write_en_w && (wr_addr_w[7:0] == `STATUS))
    status_wr_q <= 1'b1;
else
    status_wr_q <= 1'b0;

// status_y_pos [external]
wire [15:0]  status_y_pos_out_w = wr_data_q[`STATUS_Y_POS_R];


// status_h_pos [external]
wire [15:0]  status_h_pos_out_w = wr_data_q[`STATUS_H_POS_R];


//-----------------------------------------------------------------
// Register frame_buffer
//-----------------------------------------------------------------
reg frame_buffer_wr_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    frame_buffer_wr_q <= 1'b0;
else if (write_en_w && (wr_addr_w[7:0] == `FRAME_BUFFER))
    frame_buffer_wr_q <= 1'b1;
else
    frame_buffer_wr_q <= 1'b0;

// frame_buffer_addr [internal]
reg [23:0]  frame_buffer_addr_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    frame_buffer_addr_q <= (VIDEO_FB_RAM / 256);
else if (write_en_w && (wr_addr_w[7:0] == `FRAME_BUFFER))
    frame_buffer_addr_q <= cfg_wdata_i[`FRAME_BUFFER_ADDR_R];

wire [23:0]  frame_buffer_addr_out_w = frame_buffer_addr_q;


wire [15:0]  status_y_pos_in_w;
wire [15:0]  status_h_pos_in_w;


//-----------------------------------------------------------------
// Read mux
//-----------------------------------------------------------------
reg [31:0] data_r;

always @ *
begin
    data_r = 32'b0;

    case (cfg_araddr_i[7:0])

    `CONFIG:
    begin
        data_r[`CONFIG_X2_MODE_R] = config_x2_mode_q;
        data_r[`CONFIG_INT_EN_SOF_R] = config_int_en_sof_q;
        data_r[`CONFIG_ENABLE_R] = config_enable_q;
    end
    `STATUS:
    begin
        data_r[`STATUS_Y_POS_R] = status_y_pos_in_w;
        data_r[`STATUS_H_POS_R] = status_h_pos_in_w;
    end
    `FRAME_BUFFER:
    begin
        data_r[`FRAME_BUFFER_ADDR_R] = frame_buffer_addr_q;
    end
    default :
        data_r = 32'b0;
    endcase
end

//-----------------------------------------------------------------
// RVALID
//-----------------------------------------------------------------
reg rvalid_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    rvalid_q <= 1'b0;
else if (read_en_w)
    rvalid_q <= 1'b1;
else if (cfg_rready_i)
    rvalid_q <= 1'b0;

assign cfg_rvalid_o = rvalid_q;

//-----------------------------------------------------------------
// Retime read response
//-----------------------------------------------------------------
reg [31:0] rd_data_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    rd_data_q <= 32'b0;
else if (!cfg_rvalid_o || cfg_rready_i)
    rd_data_q <= data_r;

assign cfg_rdata_o = rd_data_q;
assign cfg_rresp_o = 2'b0;

//-----------------------------------------------------------------
// BVALID
//-----------------------------------------------------------------
reg bvalid_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    bvalid_q <= 1'b0;
else if (write_en_w)
    bvalid_q <= 1'b1;
else if (cfg_bready_i)
    bvalid_q <= 1'b0;

assign cfg_bvalid_o = bvalid_q;
assign cfg_bresp_o  = 2'b0;


wire status_wr_req_w = status_wr_q;

//-----------------------------------------------------------------
// Video Timings
//-----------------------------------------------------------------
localparam H_REZ         = VIDEO_WIDTH;
localparam V_REZ         = VIDEO_HEIGHT;
localparam CLK_MHZ       = (VIDEO_WIDTH == 640 && VIDEO_REFRESH == 60)  ? 25.175 :
                           (VIDEO_WIDTH == 640 && VIDEO_REFRESH == 85)  ? 36 :
                           (VIDEO_WIDTH == 800 && VIDEO_REFRESH == 72)  ? 50.00  :
                           (VIDEO_WIDTH == 1280 && VIDEO_REFRESH == 60) ? 74.25  :
                           (VIDEO_WIDTH == 1920 && VIDEO_REFRESH == 60) ? 148.5  :
                           (VIDEO_WIDTH == 1024 && VIDEO_REFRESH == 60) ? 49  :
                                                                          0;
localparam H_SYNC_START  = (VIDEO_WIDTH == 640 && VIDEO_REFRESH == 60)  ? 656 :
                           (VIDEO_WIDTH == 640 && VIDEO_REFRESH == 85)  ? 672 :
                           (VIDEO_WIDTH == 800 && VIDEO_REFRESH == 72)  ? 856 :
                           (VIDEO_WIDTH == 1280 && VIDEO_REFRESH == 60) ? 1390:
                           (VIDEO_WIDTH == 1920 && VIDEO_REFRESH == 60) ? 2008:
                           (VIDEO_WIDTH == 1024 && VIDEO_REFRESH == 60) ? 1056:
                                                                          0;
localparam H_SYNC_END    = (VIDEO_WIDTH == 640 && VIDEO_REFRESH == 60)  ? 752 :
                           (VIDEO_WIDTH == 640 && VIDEO_REFRESH == 85)  ? 720 :
                           (VIDEO_WIDTH == 800 && VIDEO_REFRESH == 72)  ? 976 :
                           (VIDEO_WIDTH == 1280 && VIDEO_REFRESH == 60) ? 1430:
                           (VIDEO_WIDTH == 1920 && VIDEO_REFRESH == 60) ? 2052:
                           (VIDEO_WIDTH == 1024 && VIDEO_REFRESH == 60) ? 1156:
                                                                          0;
localparam H_MAX         = (VIDEO_WIDTH == 640 && VIDEO_REFRESH == 60)  ? 800 :
                           (VIDEO_WIDTH == 640 && VIDEO_REFRESH == 85)  ? 832 :
                           (VIDEO_WIDTH == 800 && VIDEO_REFRESH == 72)  ? 1040:
                           (VIDEO_WIDTH == 1280 && VIDEO_REFRESH == 60) ? 1650:
                           (VIDEO_WIDTH == 1920 && VIDEO_REFRESH == 60) ? 2200:
                           (VIDEO_WIDTH == 1024 && VIDEO_REFRESH == 60) ? 1312:
                                                                          0;
localparam V_SYNC_START  = (VIDEO_HEIGHT == 480 && VIDEO_REFRESH == 60) ? 490 :
                           (VIDEO_HEIGHT == 480 && VIDEO_REFRESH == 85) ? 490 :
                           (VIDEO_HEIGHT == 600 && VIDEO_REFRESH == 72) ? 637 :
                           (VIDEO_HEIGHT == 720 && VIDEO_REFRESH == 60) ? 725 :
                           (VIDEO_HEIGHT == 1080 && VIDEO_REFRESH == 60)? 1084 :
                           (VIDEO_HEIGHT == 600 && VIDEO_REFRESH == 60)? 620 :
                                                                          0;
localparam V_SYNC_END    = (VIDEO_HEIGHT == 480 && VIDEO_REFRESH == 60) ? 492 :
                           (VIDEO_HEIGHT == 480 && VIDEO_REFRESH == 85) ? 492 :
                           (VIDEO_HEIGHT == 600 && VIDEO_REFRESH == 72) ? 643 :
                           (VIDEO_HEIGHT == 720 && VIDEO_REFRESH == 60) ? 730 :
                           (VIDEO_HEIGHT == 1080 && VIDEO_REFRESH == 60)? 1089:
                           (VIDEO_HEIGHT == 600 && VIDEO_REFRESH == 60)? 622:
                                                                          0;
localparam V_MAX         = (VIDEO_HEIGHT == 480 && VIDEO_REFRESH == 60) ? 525 :
                           (VIDEO_HEIGHT == 480 && VIDEO_REFRESH == 85) ? 525 :
                           (VIDEO_HEIGHT == 600 && VIDEO_REFRESH == 72) ? 666 :
                           (VIDEO_HEIGHT == 720 && VIDEO_REFRESH == 60) ? 750 :
                           (VIDEO_HEIGHT == 1080 && VIDEO_REFRESH == 60)? 1125:
                           (VIDEO_HEIGHT == 600 && VIDEO_REFRESH == 60)? 630:
                                                                          0;

localparam VIDEO_SIZE    = (H_REZ * V_REZ) * 2; // RG565
localparam BUFFER_SIZE   = 1024;
localparam BURST_LEN     = 32;

//-----------------------------------------------------------------
// HSYNC, VSYNC
//-----------------------------------------------------------------
reg [11:0] h_pos_q;
reg [11:0] v_pos_q;
reg        h_sync_q;
reg        v_sync_q;
reg        active_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    h_pos_q  <= 12'b0;
else if (h_pos_q == H_MAX)
    h_pos_q  <= 12'b0;
else
    h_pos_q  <= h_pos_q + 12'd1;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    v_pos_q  <= 12'b0;
else if (h_pos_q == H_MAX)
begin
    if (v_pos_q == V_MAX)
        v_pos_q  <= 12'b0;
    else
        v_pos_q  <= v_pos_q + 12'd1;
end

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    h_sync_q  <= 1'b0;
else if (h_pos_q >= H_SYNC_START && h_pos_q < H_SYNC_END)
    h_sync_q  <= 1'b1;
else
    h_sync_q  <= 1'b0;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    v_sync_q  <= 1'b0;
else if (v_pos_q >= V_SYNC_START && v_pos_q < V_SYNC_END)
    v_sync_q  <= 1'b1;
else
    v_sync_q  <= 1'b0;

wire  blanking_w = (h_pos_q < H_REZ && v_pos_q < V_REZ) ? 1'b0 : 1'b1;

assign status_h_pos_in_w = {4'b0, h_pos_q};
assign status_y_pos_in_w = {4'b0, v_pos_q};

//-----------------------------------------------------------------
// Pixel fetch FIFO
//-----------------------------------------------------------------
wire        pixel_valid_w;
wire [31:0] pixel_data_w;
wire        pixel_accept_w;
wire        pixel_pop_w    = pixel_accept_w || ~active_q;

dvi_framebuffer_fifo
u_fifo
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.push_i(outport_rvalid_i)
    ,.data_in_i(outport_rdata_i)
    ,.accept_o()

    ,.valid_o(pixel_valid_w)
    ,.data_out_o(pixel_data_w)
    ,.pop_i(pixel_pop_w)
);

//-----------------------------------------------------------------
// Enable
//-----------------------------------------------------------------
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    active_q  <= 1'b0;
else if (pixel_accept_w && !pixel_valid_w)
    active_q  <= 1'b0; // Underrun - abort until next frame
else if (h_pos_q == H_REZ && v_pos_q == V_REZ)
    active_q  <= config_enable_out_w;
else if (!config_enable_out_w)
    active_q  <= 1'b0;

//-----------------------------------------------------------------
// FIFO allocation
//-----------------------------------------------------------------
reg [15:0] allocated_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    allocated_q  <= 16'b0;
else if (outport_arvalid_o && outport_arready_i)
begin
    if (pixel_valid_w && pixel_pop_w)
        allocated_q  <= allocated_q + {6'b0, outport_arlen_o, 2'b0};
    else
        allocated_q  <= allocated_q + {6'b0, (outport_arlen_o + 8'd1), 2'b0};
end
else if (pixel_valid_w && pixel_pop_w)
    allocated_q  <= allocated_q - 16'd4;

//-----------------------------------------------------------------
// AXI Request
//-----------------------------------------------------------------
wire        fifo_space_w = (allocated_q <= (BUFFER_SIZE - BURST_LEN));
wire [31:0] frame_addr_w = {frame_buffer_addr_out_w, 8'b0};

reg        arvalid_q;
reg [31:0] araddr_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    arvalid_q <= 1'b0;
else if (outport_arvalid_o && outport_arready_i)
    arvalid_q <= 1'b0;
else if (!outport_arvalid_o && fifo_space_w && active_q)
    arvalid_q <= 1'b1;

assign outport_arvalid_o = arvalid_q;

// Calculate number of bytes being fetch (burst length x interface width)
wire [31:0] fetch_bytes_w = {22'b0, (outport_arlen_o + 8'd1), 2'b0};

reg [11:0] fetch_h_pos_q;
reg [11:0] fetch_v_pos_q;

localparam H_LINE_LEN_X2       = ((H_REZ / 2) - (BURST_LEN / 2));
localparam H_LINE_LEN_X2_BYTES = H_LINE_LEN_X2 * 2;

localparam H_FETCHES_LINE      = ((H_REZ * 2) / BURST_LEN);
localparam H_FETCHES_LINE_X2   = ((H_REZ * 2) / BURST_LEN) / 2;

wire last_fetch_w = config_x2_mode_out_w ? ((fetch_h_pos_q == (H_FETCHES_LINE_X2 - 1)) && (fetch_v_pos_q == (V_REZ - 1))) :
                                           ((fetch_h_pos_q == (H_FETCHES_LINE - 1))    && (fetch_v_pos_q == (V_REZ - 1)));

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    fetch_h_pos_q    <= 12'b0;
else if (outport_arvalid_o && outport_arready_i)
begin
    if (config_x2_mode_out_w && fetch_h_pos_q == (H_FETCHES_LINE_X2 - 1))
        fetch_h_pos_q    <= 12'b0;
    else if (!config_x2_mode_out_w && fetch_h_pos_q == (H_FETCHES_LINE - 1))
        fetch_h_pos_q  <= 12'b0;
    else
        fetch_h_pos_q  <= fetch_h_pos_q + 12'd1;
end
else if (!active_q)
    fetch_h_pos_q    <= 12'b0;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    fetch_v_pos_q    <= 12'b0;
else if (outport_arvalid_o && outport_arready_i)
begin
    if ((config_x2_mode_out_w && fetch_h_pos_q == (H_FETCHES_LINE_X2 - 1)) ||
       (!config_x2_mode_out_w && fetch_h_pos_q == (H_FETCHES_LINE - 1)))
    begin
        if (fetch_v_pos_q == (V_REZ - 1))
            fetch_v_pos_q <= 12'b0;
        else
            fetch_v_pos_q <= fetch_v_pos_q + 12'd1;
    end
end
else if (!active_q)
    fetch_v_pos_q    <= 12'b0;


always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    araddr_q <= 32'b0;
else if (outport_arvalid_o && outport_arready_i)
begin
    if (last_fetch_w)
        araddr_q  <= frame_addr_w;
    else if (config_x2_mode_out_w && !fetch_v_pos_q[0] && fetch_h_pos_q == (H_FETCHES_LINE_X2 - 1))
        araddr_q  <= araddr_q - H_LINE_LEN_X2_BYTES;
    else
        araddr_q  <= araddr_q + fetch_bytes_w;
end
else if (!active_q)
    araddr_q <= frame_addr_w;

assign outport_araddr_o  = araddr_q;
assign outport_arburst_o = 2'b01;
assign outport_arid_o    = 4'd0;
assign outport_arlen_o   = (BURST_LEN / 4) - 1;

assign outport_rready_o  = 1'b1;

// Unused
assign outport_awvalid_o = 1'b0;
assign outport_awaddr_o  = 32'b0;
assign outport_awid_o    = 4'b0;
assign outport_awlen_o   = 8'b0;
assign outport_awburst_o = 2'b0;
assign outport_wvalid_o  = 1'b0;
assign outport_wdata_o   = 32'b0;
assign outport_wstrb_o   = 4'b0;
assign outport_wlast_o   = 1'b0;
assign outport_bready_o  = 1'b0;

//-----------------------------------------------------------------
// RGB expansion
//-----------------------------------------------------------------
reg word_sel_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    word_sel_q  <= 1'b0;
else if (!blanking_w && (h_pos_q[0] || !config_x2_mode_out_w))
    word_sel_q  <= ~word_sel_q;
else if (!active_q)
    word_sel_q  <= 1'b0;

wire [7:0] blue_w   = (config_enable_out_w == 1'b0) ? 8'b0 : 
                       word_sel_q                   ? {pixel_data_w[4+16:0+16],   3'b0} : 
                                                      {pixel_data_w[4:0],         3'b0};
wire [7:0] green_w  = (config_enable_out_w == 1'b0) ? 8'b0 : 
                       word_sel_q                   ? {pixel_data_w[10+16:5+16],  2'b0} : 
                                                      {pixel_data_w[10:5],        2'b0};
wire [7:0] red_w   = (config_enable_out_w == 1'b0) ? 8'b0 : 
                       word_sel_q                   ? {pixel_data_w[15+16:11+16], 3'b0} : 
                                                      {pixel_data_w[15:11],       3'b0};

assign pixel_accept_w = ~blanking_w & word_sel_q & (h_pos_q[0] || !config_x2_mode_out_w) & active_q;

//-----------------------------------------------------------------
// DVI output
//-----------------------------------------------------------------
dvi u_dvi
(
    .clk_i(clk_i),
    .rst_i(rst_i),
    .clk_x5_i(clk_x5_i),
    .vga_red_i(red_w),
    .vga_green_i(green_w),
    .vga_blue_i(blue_w),
    .vga_blank_i(blanking_w),
    .vga_hsync_i(h_sync_q),
    .vga_vsync_i(v_sync_q),
    .dvi_red_o(dvi_red_o),
    .dvi_green_o(dvi_green_o),
    .dvi_blue_o(dvi_blue_o),
    .dvi_clock_o(dvi_clock_o)
);

//-----------------------------------------------------------------
// Interrupt output
//-----------------------------------------------------------------
reg intr_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    intr_q <= 1'b0;
else if (config_int_en_sof_out_w && fetch_h_pos_q == 12'b0 && fetch_v_pos_q == 12'b0)
    intr_q <= 1'b1;
else
    intr_q <= 1'b0;

assign intr_o = intr_q;


endmodule
