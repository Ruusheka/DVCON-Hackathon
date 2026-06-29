//==============================================================================
// axi4_master.v
//==============================================================================

module axi4_master #(
    parameter ADDR_WIDTH    = 64,
    parameter DATA_WIDTH    = 64,
    parameter ID_WIDTH      = 12,
    parameter MAX_BURST_LEN = 16     
)(
    input  wire                      ACLK,
    input  wire                      ARESETN,

    // ---------------- Read Address Channel ---------------------------------
    output reg  [ID_WIDTH-1:0]       ARID,
    output reg  [ADDR_WIDTH-1:0]     ARADDR,
    output reg  [7:0]                ARLEN,
    output wire [2:0]                ARSIZE,
    output wire [1:0]                ARBURST,
    output reg                       ARVALID,
    input  wire                      ARREADY,

    // ---------------- Read Data Channel ------------------------------------
    input  wire [ID_WIDTH-1:0]       RID,
    input  wire [DATA_WIDTH-1:0]     RDATA,
    input  wire [1:0]                RRESP,
    input  wire                      RLAST,
    input  wire                      RVALID,
    output reg                       RREADY,

    // ---------------- Control interface ------------------------------------
    input  wire                      rd_start,
    input  wire [ADDR_WIDTH-1:0]     rd_base_addr,
    input  wire [31:0]               rd_total_bytes,
    output wire                      rd_busy,
    output reg                       rd_done,

    // ---------------- Streaming data out -----------------------------------
    output reg                       m_data_valid,
    output reg  [DATA_WIDTH-1:0]     m_data,
    output reg                       m_data_last,
    input  wire                      m_data_ready
);

    assign ARSIZE  = 3'b011;  // 8 bytes/beat (DATA_WIDTH = 64)
    assign ARBURST = 2'b01;   // INCR

    localparam S_IDLE       = 2'd0,
               S_ISSUE_AR   = 2'd1,
               S_READ_BURST = 2'd2;

    reg [1:0]             state;
    reg [ADDR_WIDTH-1:0]  cur_addr;
    reg [31:0]            bytes_left;      
    reg [ID_WIDTH-1:0]    rid_counter;
    reg [7:0]             burst_beats_rem; 

    wire [31:0] beats_left_total = bytes_left >> 3;                 
    wire [31:0] beats_this_burst = (beats_left_total > MAX_BURST_LEN)
                                      ? MAX_BURST_LEN : beats_left_total;

    assign rd_busy = (state != S_IDLE);

    // ---------------- Datapath & Sequential State Machine ----------------
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            state           <= S_IDLE;
            cur_addr        <= {ADDR_WIDTH{1'b0}};
            bytes_left      <= 32'd0;
            burst_beats_rem <= 8'd0;
            rid_counter     <= {ID_WIDTH{1'b0}};
            ARID            <= {ID_WIDTH{1'b0}};
            ARADDR          <= {ADDR_WIDTH{1'b0}};
            ARLEN           <= 8'd0;
            ARVALID         <= 1'b0;
            RREADY          <= 1'b0;
            m_data_valid    <= 1'b0;
            m_data          <= {DATA_WIDTH{1'b0}};
            m_data_last     <= 1'b0;
            rd_done         <= 1'b0;
        end else begin
            // Strobes default to 0 unless explicitly active
            rd_done      <= 1'b0;
            m_data_valid <= 1'b0;
            m_data_last  <= 1'b0;

            case (state)
                S_IDLE: begin
                    ARVALID <= 1'b0;
                    RREADY  <= 1'b0;
                    if (rd_start) begin
                        cur_addr   <= rd_base_addr;
                        bytes_left <= rd_total_bytes;
                        state      <= S_ISSUE_AR;
                    end
                end

                S_ISSUE_AR: begin
                    ARID    <= rid_counter;
                    ARADDR  <= cur_addr;
                    ARLEN   <= beats_this_burst[7:0] - 8'd1; 
                    RREADY  <= 1'b0;
                    
                    if (ARVALID && ARREADY) begin
                        $display("%0t ARLEN=%0d (beats=%0d)", $time, ARLEN, ARLEN+1);
                        burst_beats_rem <= beats_this_burst[7:0];
                        rid_counter     <= rid_counter + 1'b1;
                        ARVALID         <= 1'b0;
                        state           <= S_READ_BURST;
                    end else begin
                        ARVALID <= 1'b1; 
                    end
                end

                S_READ_BURST: begin
                    RREADY <= m_data_ready;

                    if (RVALID && RREADY) begin
                        $display("%0t RVALID=%b RREADY=%b RLAST=%b bytes_left=%0d burst_beats_rem=%0d",
                                 $time, RVALID, RREADY, RLAST, bytes_left, burst_beats_rem);

                        m_data_valid    <= 1'b1;
                        m_data          <= RDATA;
                        cur_addr        <= cur_addr + 64'd8;
                        bytes_left      <= bytes_left - 32'd8;
                        burst_beats_rem <= burst_beats_rem - 8'd1;

                        // Check global completion conditions safely on the active clock edge
                        if (bytes_left == 32'd8) begin
                            $display("%0t RD_DONE generated via precise byte tracking", $time);
                            m_data_last <= 1'b1;
                            rd_done      <= 1'b1;
                            RREADY       <= 1'b0;
                            state        <= S_IDLE;
                            $display("%0t >>> rd_done asserted <<<", $time);
                        end else if (burst_beats_rem == 8'd1) begin
                            RREADY       <= 1'b0;
                            state        <= S_ISSUE_AR;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
