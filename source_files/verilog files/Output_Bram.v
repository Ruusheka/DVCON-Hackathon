`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: Output_BRAM
// Description: Dual-Port Block RAM to capture and store the pooled results.
//              Optimized with explicit loop clearing on reset for deterministic 
//              simulation waves.
//////////////////////////////////////////////////////////////////////////////////

module Output_BRAM(
    input clk,
    input rst,

    // Write Port A (Connected to Pipeline Output)
    input pool_valid,
    input [15:0] pool_out,

    // Read Port B (Connected to Downstream AXI Master / VEGA)
    input [5:0] read_addr,
    output reg [15:0] read_data
);

// Memory Array (64 addresses deep)
reg [15:0] ram_matrix [0:63];
reg [5:0]  write_addr;

integer i;

// Port A: Synchronous Pipeline Logging
always @(posedge clk)
begin
    if(rst)
    begin
        write_addr <= 6'd0;
        for(i = 0; i < 64; i = i + 1) begin
            ram_matrix[i] <= 16'd0; // Clears all X states on reset!
        end
    end
    else if(pool_valid)
    begin
        ram_matrix[write_addr] <= pool_out;
        write_addr             <= write_addr + 1;
    end
end

// Port B: Independent Read Interface
always @(posedge clk)
begin
    read_data <= ram_matrix[read_addr];
end

endmodule