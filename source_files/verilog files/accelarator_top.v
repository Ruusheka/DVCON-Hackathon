`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: Accelerator_Top
// Description: Full streaming hardware CNN pipeline wrapper with aligned 
//              handshake registers and integrated Output BRAM storage.
//////////////////////////////////////////////////////////////////////////////////

module Accelerator_Top(
    input clk,
    input rst,

    // 64-Bit Incoming Data Interface
    input [63:0] pixel_bus,
    input pixel_valid,

    // External Port B BRAM Read Access (For Downstream AXI Master / VEGA)
    input [5:0] external_read_addr,
    output [15:0] external_read_data,

    // Aligned Output Pipeline Status Checkpins
    output pool_valid_out,
    output [15:0] final_output
);

// 256-Bit Row Interconnect Data Buses
wire [255:0] line0;
wire [255:0] line1;
wire [255:0] line2;

// 3x3 Window Extraction Pixel Paths
wire [7:0] p0, p1, p2;
wire [7:0] p3, p4, p5;
wire [7:0] p6, p7, p8;

// Pipeline Interconnect Valid and Done Handshake Wires
wire row0_full;
wire row1_full;
wire row2_full;
wire window_valid;
wire window_done;
wire conv_valid;
wire relu_valid;
wire pool_valid_mesh; // Direct wire output from Max Pooling module

// Pipeline Computed Data Wires
wire signed [15:0] conv_out;
wire [15:0] relu_out;
wire [15:0] pool_out;

// Perfectly Synchronized Output Registers
reg [15:0] final_output_reg;
reg        pool_valid_reg;

//----------------------------------------------------------------
// Stage 1: Line Buffer Storage Matrix
//----------------------------------------------------------------
FPGA_BRAM_line_buffers LB (
    .clk(clk),
    .rst(rst),
    .load_enable(1'b1),
    .window_done(window_done),
    .pixel_bus(pixel_bus),
    .pixel_valid(pixel_valid),
    .line0(line0),
    .line1(line1),
    .line2(line2),
    .row0_full(row0_full),
    .row1_full(row1_full),
    .row2_full(row2_full)
);

//----------------------------------------------------------------
// Stage 2: Sliding 3x3 Extraction Matrix Generator
//----------------------------------------------------------------
Window_Generator WS (
    .clk(clk),
    .rst(rst),
    .line0(line0),
    .line1(line1),
    .line2(line2),
    .row0_full(row0_full),
    .row1_full(row1_full),
    .row2_full(row2_full),
    .window_valid(window_valid),
    .window_done(window_done),
    .p0(p0), .p1(p1), .p2(p2),
    .p3(p3), .p4(p4), .p5(p5),
    .p6(p6), .p7(p7), .p8(p8)
);

//----------------------------------------------------------------
// Stage 3: Convolutional Multiply-Accumulate Operator (1-Cycle Latency)
//----------------------------------------------------------------
MAC_Convolution MAC (
    .clk(clk),
    .rst(rst),
    .p0(p0), .p1(p1), .p2(p2),
    .p3(p3), .p4(p4), .p5(p5),
    .p6(p6), .p7(p7), .p8(p8),
    .window_valid(window_valid),
    .conv_valid(conv_valid),
    .conv_out(conv_out)
);

//----------------------------------------------------------------
// Stage 4: Rectified Linear Unit Latch Layer (1-Cycle Latency)
//----------------------------------------------------------------
Relu RELU (
    .clk(clk),
    .rst(rst),
    .data_in(conv_out),
    .conv_valid(conv_valid),
    .relu_valid(relu_valid),
    .data_out(relu_out)
);

//----------------------------------------------------------------
// Stage 5: Streaming Max Pooling Array Latch
//----------------------------------------------------------------
Max_pooling MP (
    .clk(clk),
    .rst(rst),
    .relu_valid(relu_valid),
    .relu_out(relu_out),
    .pool_valid(pool_valid_mesh),
    .pool_out(pool_out)
);

//----------------------------------------------------------------
// Stage 6: Integrated Output Storage Block RAM
//----------------------------------------------------------------
Output_BRAM BRAM_Storage (
    .clk(clk),
    .rst(rst),
    .pool_valid(pool_valid_mesh), // Direct wire connect to catch data natively
    .pool_out(pool_out),
    .read_addr(external_read_addr),
    .read_data(external_read_data)
);

//----------------------------------------------------------------
// Output Registration Phase Sync: Aligns Control and Data completely
//----------------------------------------------------------------
always @(posedge clk)
begin
    if(rst)
    begin
        pool_valid_reg   <= 1'b0;
        final_output_reg <= 16'd0;
    end
    else
    begin
        pool_valid_reg <= pool_valid_mesh; // Shifts flag exactly 1 cycle out
        
        if(pool_valid_mesh)
            final_output_reg <= pool_out;  // Shifts data exactly 1 cycle out
    end
end

assign final_output   = final_output_reg;
assign pool_valid_out = pool_valid_reg;

endmodule