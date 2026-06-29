`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 19.06.2026 17:41:16
// Design Name: 
// Module Name: MAC_operations
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module MAC_Convolution(

    input clk,
    input rst,

    input signed [7:0] p0,
    input signed [7:0] p1,
    input signed [7:0] p2,
    input signed [7:0] p3,
    input signed [7:0] p4,
    input signed [7:0] p5,
    input signed [7:0] p6,
    input signed [7:0] p7,
    input signed [7:0] p8,
    
    input window_valid,
    
    output reg conv_valid,

    output reg signed [15:0] conv_out

);

parameter signed [7:0] w0 = -1;
parameter signed [7:0] w1 = -2;
parameter signed [7:0] w2 = -1;

parameter signed [7:0] w3 = 0;
parameter signed [7:0] w4 = 0;
parameter signed [7:0] w5 = 0;

parameter signed [7:0] w6 = 1;
parameter signed [7:0] w7 = 2;
parameter signed [7:0] w8 = 1;

reg signed [15:0] sum;

wire signed [15:0] mac_result;
assign mac_result = (p0*w0) + (p1*w1) + (p2*w2) + (p3*w3) + (p4*w4) + (p5*w5) + (p6*w6) + (p7*w7) + (p8*w8);

always @(posedge clk)
begin

    if(rst)
    begin
        conv_out <= 0;
        conv_valid <= 0;
    end

    else
    begin
        conv_valid <= window_valid;
        
        if(window_valid)
        begin
            conv_out <= mac_result;
        end

    end

end

endmodule