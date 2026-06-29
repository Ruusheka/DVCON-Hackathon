`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: Max_pooling
// Description: Streaming Max Pooling Layer using explicit cycle tracking.
//              Accumulates 4 sequential streaming pixels over 4 clock cycles,
//              computes the peak value, and asserts pool_valid.
//////////////////////////////////////////////////////////////////////////////////

module Max_pooling(
    input clk,
    input rst,

    input relu_valid,
    input [15:0] relu_out,

    output reg pool_valid,
    output reg [15:0] pool_out
);

reg [15:0] running_max;
reg [1:0]  count;

always @(posedge clk) 
begin
    if(rst) 
    begin
        running_max <= 16'd0;
        count       <= 2'd0;
        pool_out    <= 16'd0;
        pool_valid  <= 1'b0;
    end 
    else 
    begin
        pool_valid <= 1'b0; // Default fallback pulse state: low

        if(relu_valid) 
        begin
            case(count)
                2'd0: 
                begin 
                    running_max <= relu_out; 
                    count       <= 2'd1; 
                end
                
                2'd1: 
                begin
                    if(relu_out > running_max) 
                        running_max <= relu_out;
                    count <= 2'd2;
                end
                
                2'd2: 
                begin
                    if(relu_out > running_max) 
                        running_max <= relu_out;
                    count <= 2'd3;
                end
                
                2'd3: 
                begin
                    pool_out   <= (relu_out > running_max) ? relu_out : running_max;
                    pool_valid <= 1'b1; // Pulse high for exactly 1 cycle
                    count      <= 2'd0;
                    running_max <= 16'd0;
                end
            endcase
        end
    end
end

endmodule