`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: FPGA_BRAM_line_buffers
// Description: Fixed Line Buffer using Direct Indexing (Raster Order). 
//              No shifting. Uses burst_counter to route pixels directly to the
//              correct array slots (0-7, 8-15, 16-23, 24-31).
//////////////////////////////////////////////////////////////////////////////////

module FPGA_BRAM_line_buffers(
    input clk,
    input rst,
    
    input load_enable,
    input window_done,      // Clears line buffer flags to load next 3 rows

    input [63:0] pixel_bus,
    input pixel_valid,

    // 256-bit full row outputs for the Window Generator
    output [255:0] line0,
    output [255:0] line1,
    output [255:0] line2,

    output reg row0_full,
    output reg row1_full,
    output reg row2_full
);

// Memory arrays for 32 pixels per row
reg [7:0] row0 [0:31];
reg [7:0] row1 [0:31];
reg [7:0] row2 [0:31];

reg [1:0] burst_counter; // Tracks which of the 4 bursts we are receiving
reg [1:0] fill_state;    // Tracks which row we are filling (0=row2, 1=row1, 2=row0)

integer i;

//------------------------------------------------------
// Unpack incoming 64-bit AXI data bus into 8 individual pixels
//------------------------------------------------------
wire [7:0] pix0 = pixel_bus[7:0];
wire [7:0] pix1 = pixel_bus[15:8];
wire [7:0] pix2 = pixel_bus[23:16];
wire [7:0] pix3 = pixel_bus[31:24];
wire [7:0] pix4 = pixel_bus[39:32];
wire [7:0] pix5 = pixel_bus[47:40];
wire [7:0] pix6 = pixel_bus[55:48];
wire [7:0] pix7 = pixel_bus[63:56];

always @(posedge clk)
begin
    if(rst)
    begin
        burst_counter <= 0;
        fill_state    <= 0;

        row0_full     <= 0;
        row1_full     <= 0;
        row2_full     <= 0;

        for(i=0; i<32; i=i+1)
        begin
            row0[i] <= 0;
            row1[i] <= 0;
            row2[i] <= 0;
        end
    end
    else 
    begin
        //--------------------------------------------------
        // Self-Clearing Lifecycle: Reset flags when window completes
        //--------------------------------------------------
        if(window_done)
        begin
            row0_full     <= 0;
            row1_full     <= 0;
            row2_full     <= 0;

            burst_counter <= 0;
            fill_state    <= 0;
        end
        //--------------------------------------------------
        // Write incoming pixels based on current row state and burst index
        //--------------------------------------------------
        else if(pixel_valid && load_enable)
        begin
            
            case(fill_state)
            //----------------------------------------------
            // Filling Row 2 (Direct Pointer Mapping)
            //----------------------------------------------
            2'd0: begin
                case(burst_counter)
                    2'd0: begin
                        row2[0]<=pix0; row2[1]<=pix1; row2[2]<=pix2; row2[3]<=pix3;
                        row2[4]<=pix4; row2[5]<=pix5; row2[6]<=pix6; row2[7]<=pix7;
                    end
                    2'd1: begin
                        row2[8]<=pix0;  row2[9]<=pix1;  row2[10]<=pix2; row2[11]<=pix3;
                        row2[12]<=pix4; row2[13]<=pix5; row2[14]<=pix6; row2[15]<=pix7;
                    end
                    2'd2: begin
                        row2[16]<=pix0; row2[17]<=pix1; row2[18]<=pix2; row2[19]<=pix3;
                        row2[20]<=pix4; row2[21]<=pix5; row2[22]<=pix6; row2[23]<=pix7;
                    end
                    2'd3: begin
                        row2[24]<=pix0; row2[25]<=pix1; row2[26]<=pix2; row2[27]<=pix3;
                        row2[28]<=pix4; row2[29]<=pix5; row2[30]<=pix6; row2[31]<=pix7;
                    end
                endcase
            end

            //----------------------------------------------
            // Filling Row 1 (Direct Pointer Mapping)
            //----------------------------------------------
            2'd1: begin
                case(burst_counter)
                    2'd0: begin
                        row1[0]<=pix0; row1[1]<=pix1; row1[2]<=pix2; row1[3]<=pix3;
                        row1[4]<=pix4; row1[5]<=pix5; row1[6]<=pix6; row1[7]<=pix7;
                    end
                    2'd1: begin
                        row1[8]<=pix0;  row1[9]<=pix1;  row1[10]<=pix2; row1[11]<=pix3;
                        row1[12]<=pix4; row1[13]<=pix5; row1[14]<=pix6; row1[15]<=pix7;
                    end
                    2'd2: begin
                        row1[16]<=pix0; row1[17]<=pix1; row1[18]<=pix2; row1[19]<=pix3;
                        row1[20]<=pix4; row1[21]<=pix5; row1[22]<=pix6; row1[23]<=pix7;
                    end
                    2'd3: begin
                        row1[24]<=pix0; row1[25]<=pix1; row1[26]<=pix2; row1[27]<=pix3;
                        row1[28]<=pix4; row1[29]<=pix5; row1[30]<=pix6; row1[31]<=pix7;
                    end
                endcase
            end

            //----------------------------------------------
            // Filling Row 0 (Direct Pointer Mapping)
            //----------------------------------------------
            2'd2: begin
                case(burst_counter)
                    2'd0: begin
                        row0[0]<=pix0; row0[1]<=pix1; row0[2]<=pix2; row0[3]<=pix3;
                        row0[4]<=pix4; row0[5]<=pix5; row0[6]<=pix6; row0[7]<=pix7;
                    end
                    2'd1: begin
                        row0[8]<=pix0;  row0[9]<=pix1;  row0[10]<=pix2; row0[11]<=pix3;
                        row0[12]<=pix4; row0[13]<=pix5; row0[14]<=pix6; row0[15]<=pix7;
                    end
                    2'd2: begin
                        row0[16]<=pix0; row0[17]<=pix1; row0[18]<=pix2; row0[19]<=pix3;
                        row0[20]<=pix4; row0[21]<=pix5; row0[22]<=pix6; row0[23]<=pix7;
                    end
                    2'd3: begin
                        row0[24]<=pix0; row0[25]<=pix1; row0[26]<=pix2; row0[27]<=pix3;
                        row0[28]<=pix4; row0[29]<=pix5; row0[30]<=pix6; row0[31]<=pix7;
                    end
                endcase
            end
            default: begin end
            endcase

            //--------------------------------------------------
            // State Machine for controlling Burst Count and Row Transitions
            //--------------------------------------------------
            if(burst_counter == 2'd3)
            begin
                burst_counter <= 0; // Reset burst counter for next row

                case(fill_state)
                2'd0: begin
                    row2_full  <= 1;
                    fill_state <= 2'd1; // Shift to Row 1
                end
                2'd1: begin
                    row1_full  <= 1;
                    fill_state <= 2'd2; // Shift to Row 0
                end
                2'd2: begin
                    row0_full  <= 1;
                    fill_state <= 2'd0; // Loop back to 0; stalls until window_done triggers
                end
                default: fill_state <= 2'd0;
                endcase
            end
            else
            begin
                burst_counter <= burst_counter + 1;
            end

        end // End of pixel_valid && load_enable
    end // End of else
end // End of always

//------------------------------------------------------
// Assign complete 256-bit buses for the window generator.
// Stitched standard MSB-to-LSB order (Index 31 down to 0)
//------------------------------------------------------
assign line0 = {
    row0[31], row0[30], row0[29], row0[28], row0[27], row0[26], row0[25], row0[24],
    row0[23], row0[22], row0[21], row0[20], row0[19], row0[18], row0[17], row0[16],
    row0[15], row0[14], row0[13], row0[12], row0[11], row0[10], row0[9],  row0[8],
    row0[7],  row0[6],  row0[5],  row0[4],  row0[3],  row0[2],  row0[1],  row0[0]
};

assign line1 = {
    row1[31], row1[30], row1[29], row1[28], row1[27], row1[26], row1[25], row1[24],
    row1[23], row1[22], row1[21], row1[20], row1[19], row1[18], row1[17], row1[16],
    row1[15], row1[14], row1[13], row1[12], row1[11], row1[10], row1[9],  row1[8],
    row1[7],  row1[6],  row1[5],  row1[4],  row1[3],  row1[2],  row1[1],  row1[0]
};

assign line2 = {
    row2[31], row2[30], row2[29], row2[28], row2[27], row2[26], row2[25], row2[24],
    row2[23], row2[22], row2[21], row2[20], row2[19], row2[18], row2[17], row2[16],
    row2[15], row2[14], row2[13], row2[12], row2[11], row2[10], row2[9],  row2[8],
    row2[7],  row2[6],  row2[5],  row2[4],  row2[3],  row2[2],  row2[1],  row2[0]
};

endmodule