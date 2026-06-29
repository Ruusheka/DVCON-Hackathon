`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: ddr_model
// Description: Behavioral, file-backed DDR stand-in for simulation. Acts as
//              an AXI4 read-only slave (matches axi4_master's port set) and
//              loads its contents from an external binary file at time 0.
//              Rewritten as a synchronous NBA-based FSM to avoid races with
//              the master's non-blocking RREADY updates.
//////////////////////////////////////////////////////////////////////////////////

module ddr_model #(
    parameter ADDR_WIDTH      = 64,
    parameter DATA_WIDTH      = 64,
    parameter ID_WIDTH        = 12,
    parameter MEM_DEPTH_BYTES = 1048576,       // size to cover your image (+ margin)
    parameter IMG_FILE        = "image.bin"    // path to the raw binary file
)(
    input  wire                      ACLK,
    input  wire                      ARESETN,

    input  wire [ID_WIDTH-1:0]       ARID,
    input  wire [ADDR_WIDTH-1:0]     ARADDR,
    input  wire [7:0]                ARLEN,
    input  wire [2:0]                ARSIZE,
    input  wire [1:0]                ARBURST,
    input  wire                      ARVALID,
    output reg                       ARREADY,

    output reg  [ID_WIDTH-1:0]       RID,
    output reg  [DATA_WIDTH-1:0]     RDATA,
    output reg  [1:0]                RRESP,
    output reg                       RLAST,
    output reg                       RVALID,
    input  wire                      RREADY
);

    reg [7:0] mem_bytes [0:MEM_DEPTH_BYTES-1];

    integer fd;
    integer bytes_read;
    integer idx;

    // -------- load the file at time 0 --------
    initial begin
        for (idx = 0; idx < MEM_DEPTH_BYTES; idx = idx + 1)
            mem_bytes[idx] = 8'd0; // zero-init so unread tail bytes are deterministic

        fd = $fopen(IMG_FILE, "rb");
        if (fd == 0) begin
            $display("[ddr_model] WARNING: could not open '%s' - memory stays zeroed", IMG_FILE);
        end else begin
            bytes_read = $fread(mem_bytes, fd);
            $fclose(fd);
            $display("[ddr_model] loaded %0d bytes from '%s'", bytes_read, IMG_FILE);
        end
    end

    // -------- behavioral AXI4 read slave (synchronous FSM) --------
    localparam S_ACCEPT_AR = 1'd0,
               S_READ_BURST = 1'd1;

    reg                   state;
    reg [ADDR_WIDTH-1:0]  cap_addr;
    reg [7:0]             cap_len;
    reg [ID_WIDTH-1:0]    cap_id;
    reg [7:0]             beat;

    // Combinational read of the 8 bytes for the *current* beat address.
    // Computed from cap_addr/beat which are registered, so this is safe
    // to use directly when loading RDATA on the next clock edge.
    function [DATA_WIDTH-1:0] read_beat;
        input [ADDR_WIDTH-1:0] addr;
        input [7:0]            beat_idx;
        reg   [ADDR_WIDTH-1:0] base;
        begin
            base = addr + (beat_idx * 8);
            read_beat = { mem_bytes[base+7], mem_bytes[base+6],
                          mem_bytes[base+5], mem_bytes[base+4],
                          mem_bytes[base+3], mem_bytes[base+2],
                          mem_bytes[base+1], mem_bytes[base+0] };
        end
    endfunction

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            state    <= S_ACCEPT_AR;
            ARREADY  <= 1'b1;
            RVALID   <= 1'b0;
            RLAST    <= 1'b0;
            RDATA    <= {DATA_WIDTH{1'b0}};
            RID      <= {ID_WIDTH{1'b0}};
            RRESP    <= 2'b00;
            cap_addr <= {ADDR_WIDTH{1'b0}};
            cap_len  <= 8'd0;
            cap_id   <= {ID_WIDTH{1'b0}};
            beat     <= 8'd0;
        end else begin
            case (state)
                // ---------------------------------------------------------
                // Wait for an address handshake. Stay ready at all times;
                // on acceptance, latch the burst and immediately register
                // the FIRST beat's data so it is valid the cycle we assert
                // RVALID (no extra latency beat, no skipped beat).
                // ---------------------------------------------------------
                S_ACCEPT_AR: begin
                    RVALID <= 1'b0;
                    RLAST  <= 1'b0;

                    if (ARVALID && ARREADY) begin
                        cap_addr <= ARADDR;
                        cap_len  <= ARLEN;
                        cap_id   <= ARID;
                        beat     <= 8'd0;

                        RDATA    <= read_beat(ARADDR, 8'd0);
                        RID      <= ARID;
                        RRESP    <= 2'b00;
                        RVALID   <= 1'b1;
                        RLAST    <= (ARLEN == 8'd0); // single-beat burst edge case

                        ARREADY  <= 1'b1; // keep accepting; no new AR will arrive mid-burst per AXI rules
                        state    <= S_READ_BURST;
                    end
                end

                // ---------------------------------------------------------
                // Drive one beat per cycle while RVALID is held; only
                // advance the beat counter / data on a completed handshake
                // (RVALID && RREADY). This is the key fix: we never look
                // at RREADY combinationally to decide what to load next -
                // we only act on it synchronously, in step with the
                // master's own NBA-driven RREADY.
                // ---------------------------------------------------------
                S_READ_BURST: begin
                    if (RVALID && RREADY) begin
                        $display("%0t DDR beat=%0d cap_len=%0d RLAST=%b",
                                  $time, beat, cap_len, RLAST);

                        if (beat == cap_len) begin
                            // Burst complete - drop VALID/LAST, go accept next AR
                            RVALID <= 1'b0;
                            RLAST  <= 1'b0;
                            state  <= S_ACCEPT_AR;
                        end else begin
                            beat   <= beat + 8'd1;
                            RDATA  <= read_beat(cap_addr, beat + 8'd1);
                            RLAST  <= ((beat + 8'd1) == cap_len);
                            RVALID <= 1'b1;
                        end
                    end
                    // If RVALID && !RREADY: hold current RDATA/RLAST/RVALID
                    // unchanged (natural due to NBA - nothing to do here).
                end

                default: state <= S_ACCEPT_AR;
            endcase
        end
    end

endmodule