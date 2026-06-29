`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: Window_Generator
// Description: Upgraded Window Generator supporting 256-bit line inputs.
//              Tracks a 5-bit column pointer to extract 30 windows (0 to 29).
//              Fixed look-ahead window_valid bug on terminal count.
//////////////////////////////////////////////////////////////////////////////////

module Window_Generator(
    input clk,
    input rst,

    // Upgraded inputs from 64-bit to 256-bit wide rows (32 columns * 8-bit pixels)
    input [255:0] line0,
    input [255:0] line1,
    input [255:0] line2,

    input row0_full,
    input row1_full,
    input row2_full,

    output reg window_valid,
    output reg window_done,     // Clear pulse signal out to Line Buffers

    // 3x3 Window Pixel Outputs
    output reg [7:0] p0, output reg [7:0] p1, output reg [7:0] p2,
    output reg [7:0] p3, output reg [7:0] p4, output reg [7:0] p5,
    output reg [7:0] p6, output reg [7:0] p7, output reg [7:0] p8
);

// Maximum legal column_ptr = 29 (Total 30 windows)
reg [4:0] column_ptr;

// Renamed for better long-term code readability
reg window_active;

always @(posedge clk)
begin
    if(rst)
    begin
        column_ptr    <= 5'd0;
        window_valid  <= 0;
        window_done   <= 0;
        window_active <= 0;

        p0 <= 8'd0; p1 <= 8'd0; p2 <= 8'd0;
        p3 <= 8'd0; p4 <= 8'd0; p5 <= 8'd0;
        p6 <= 8'd0; p7 <= 8'd0; p8 <= 8'd0;
    end
    else
    begin
        // Always default to 0 to create a crisp one-cycle pulse
        window_done <= 0;

        //-------------------------------------------------
        // Lifecycle Trigger: Start processing when all 3 rows are full
        //-------------------------------------------------
        if ((row0_full && row1_full && row2_full) || window_active)
        begin
            window_active <= 1;
            window_valid  <= 1; // Default valid high for active shifting

            //-------------------------------------------------
            // Extract 3×3 window using Indexed Part Select (+:)
            //-------------------------------------------------
            p0 <= line0[(column_ptr * 8) +: 8];
            p1 <= line0[((column_ptr + 1) * 8) +: 8];
            p2 <= line0[((column_ptr + 2) * 8) +: 8];

            p3 <= line1[(column_ptr * 8) +: 8];
            p4 <= line1[((column_ptr + 1) * 8) +: 8];
            p5 <= line1[((column_ptr + 2) * 8) +: 8];

            p6 <= line2[(column_ptr * 8) +: 8];
            p7 <= line2[((column_ptr + 1) * 8) +: 8];
            p8 <= line2[((column_ptr + 2) * 8) +: 8];

            //----------------------------------------------
            // Column Navigation & Finish Boundaries
            //----------------------------------------------
            if(column_ptr == 5'd29) 
            begin
                column_ptr    <= 5'd0;
                window_done   <= 1; // Pulse out to clear Line Buffers
                window_active <= 0; // Turn off processing flag
                window_valid  <= 0; // OVERRIDE the valid high immediately for the next cycle
            end
            else
            begin
                column_ptr <= column_ptr + 1;
            end
        end
        else
        begin
            window_valid <= 0;
        end
    end
end

endmodule