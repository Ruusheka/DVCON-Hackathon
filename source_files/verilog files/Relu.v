`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: Relu
// Description: Rectified Linear Unit activation layer. Process data strictly
//              when conv_valid is asserted, adding exactly 1 clock cycle latency.
//////////////////////////////////////////////////////////////////////////////////

module Relu(
    input clk,
    input rst,
    input signed [15:0] data_in,
    input conv_valid,
    output reg relu_valid,
    output reg [15:0] data_out
);

always @(posedge clk)
begin
    if(rst)
    begin
        data_out   <= 0;
        relu_valid <= 0;
    end
    else
    begin
        // Track the 1-cycle execution latency of the ReLU layer
        relu_valid <= conv_valid;
        
        // Process math conditionally only when valid inputs exist
        if(conv_valid)
        begin
            if(data_in < 0)
                data_out <= 16'd0;
            else
                data_out <= data_in;
        end
    end
end

endmodule