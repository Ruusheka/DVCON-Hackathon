//==============================================================================
// axi4_slave.v
// AXI4-Full Slave Interface : CNN Accelerator Control/Status Registers
// Target      : Genesys-2 (XC7K325T)
// Clock       : 50 MHz (ACLK)
// Data Width  : 64
// ID Width    : 12
// Base Addr   : 0x2006_0000  (decoded by upstream AXI interconnect/top level;
//               this slave only looks at the low 6 address bits as a
//               register offset, so make sure only in-range transactions
//               are routed here)
//
// Register Map (byte offset from BASE_ADDR):
//   0x00  CONTROL   : bit0 = START   (write-1-pulse, starts accelerator)
//                      bit1 = SW_RST (write-1-pulse, soft-resets datapath)
//   0x08  STATUS    : bit0 = BUSY    (RO, from accelerator)
//                      bit1 = DONE   (RO, sticky until cleared via IRQ_CLR)
//   0x10  TASK_ID   : task ID written by VEGA before asserting START
//   0x18  IMG_ADDR  : DDR pointer to the preprocessed image (laptop->VEGA->here)
//   0x20  RESULT    : weighted score = 0.6*confidence + 0.4*relevance (RO)
//   0x28  IRQ_CLR   : write-1-pulse to clear STATUS.DONE
//
// Notes:
//  - This is a control/status interface, so most transactions will be
//    single-beat (AWLEN/ARLEN = 0), but burst (INCR) is supported for
//    AXI4-Full compliance.
//  - Two independent FSMs (write, read) per AXI4 spec; each split into a
//    state register + next-state block, consistent with standard 2-process
//    FSM style.
//==============================================================================

module axi4_slave #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 12,
    parameter [ADDR_WIDTH-1:0] BASE_ADDR = 64'h0000_0000_2006_0000
)(
    input  wire   ACLK,
    input  wire   ARESETN,

    // ---------------- Write Address Channel ----------------
    input  wire [ID_WIDTH-1:0]       AWID,
    input  wire [ADDR_WIDTH-1:0]     AWADDR,
    input  wire [7:0]                AWLEN,
    input  wire [2:0]                AWSIZE,
    input  wire [1:0]                AWBURST,
    input  wire                      AWVALID,
    output wire                      AWREADY,

    // ---------------- Write Data Channel --------------------
    input  wire [DATA_WIDTH-1:0]     WDATA,
    input  wire [DATA_WIDTH/8-1:0]   WSTRB,
    input  wire                      WLAST,
    input  wire                      WVALID,
    output wire                      WREADY,

    // ---------------- Write Response Channel -----------------
    output wire [ID_WIDTH-1:0]       BID,
    output wire [1:0]                BRESP,
    output wire                      BVALID,
    input  wire                      BREADY,

    // ---------------- Read Address Channel --------------------
    input  wire [ID_WIDTH-1:0]       ARID,
    input  wire [ADDR_WIDTH-1:0]     ARADDR,
    input  wire [7:0]                ARLEN,
    input  wire [2:0]                ARSIZE,
    input  wire [1:0]                ARBURST,
    input  wire                      ARVALID,
    output wire                      ARREADY,

    // ---------------- Read Data Channel --------------------
    output wire [ID_WIDTH-1:0]       RID,
    output wire [DATA_WIDTH-1:0]     RDATA,
    output wire [1:0]                RRESP,
    output wire                      RLAST,
    output wire                      RVALID,
    input  wire                      RREADY,

    // ---------------- Register interface to cnn_accelerator_top ----------
    output reg                       start,         // 1-cycle pulse
    output reg                       sw_reset,       // 1-cycle pulse
    output reg  [DATA_WIDTH-1:0]     task_id_reg,
    output reg  [DATA_WIDTH-1:0]     img_addr_reg,
    input  wire                      busy,
    input  wire                      done,           // 1-cycle pulse from accelerator
    input  wire [DATA_WIDTH-1:0]     result_score
);

    // Register byte offsets
    localparam [5:0] REG_CONTROL  = 6'h00;
    localparam [5:0] REG_STATUS   = 6'h08;
    localparam [5:0] REG_TASK_ID  = 6'h10;
    localparam [5:0] REG_IMG_ADDR = 6'h18;
    localparam [5:0] REG_RESULT   = 6'h20;
    localparam [5:0] REG_IRQ_CLR  = 6'h28;

    integer i;

    // ==================================================================
    // STATUS / DONE (sticky bit, shared by both FSMs)
    // ==================================================================
    reg done_sticky;
    reg irq_clr_pulse;

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN)
            done_sticky <= 1'b0;
        else if (sw_reset)
            done_sticky <= 1'b0;
        else if (done)
            done_sticky <= 1'b1;
        else if (irq_clr_pulse)
            done_sticky <= 1'b0;
    end
    

    // ==================================================================
    // WRITE CHANNEL FSM
    // ==================================================================
    localparam W_IDLE = 2'd0,
               W_DATA = 2'd1,
               W_RESP = 2'd2;

    reg [1:0]            w_state, w_state_next;
    reg [ID_WIDTH-1:0]   awid_capture;
    reg [ADDR_WIDTH-1:0] awaddr_ptr;
    reg [2:0]            awsize_capture;
    reg [7:0]            wbeat_count;
    wire [5:0]           waddr_offset = awaddr_ptr[5:0];

    // state register
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) w_state <= W_IDLE;
        else          w_state <= w_state_next;
    end

    // next-state logic
    always @(*) begin
        w_state_next = w_state;
        case (w_state)
            W_IDLE: if (AWVALID && AWREADY) w_state_next = W_DATA;
            W_DATA: if (WVALID && WREADY && WLAST) w_state_next = W_RESP;
            W_RESP: if (BVALID && BREADY) w_state_next = W_IDLE;
            default: w_state_next = W_IDLE;
        endcase
    end

    assign AWREADY = (w_state == W_IDLE);
    assign WREADY  = (w_state == W_DATA);
    assign BVALID  = (w_state == W_RESP);
    assign BID     = awid_capture;
    assign BRESP   = 2'b00; // OKAY

    // capture AW info, advance write pointer for bursts
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            awid_capture   <= {ID_WIDTH{1'b0}};
            awaddr_ptr     <= {ADDR_WIDTH{1'b0}};
            awsize_capture <= 3'b0;
            wbeat_count    <= 8'd0;
        end else if (AWVALID && AWREADY) begin
            awid_capture   <= AWID;
            awaddr_ptr     <= AWADDR;
            awsize_capture <= AWSIZE;
            wbeat_count    <= 8'd0;
        end else if (WVALID && WREADY) begin
            awaddr_ptr  <= awaddr_ptr + (1'b1 << awsize_capture); // INCR burst
            wbeat_count <= wbeat_count + 1'b1;
        end
    end

    // register writes + control pulses
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            start         <= 1'b0;
            sw_reset      <= 1'b0;
            irq_clr_pulse <= 1'b0;
            task_id_reg   <= {DATA_WIDTH{1'b0}};
            img_addr_reg  <= {DATA_WIDTH{1'b0}};
        end else begin
            // defaults: these are 1-cycle pulses
            start         <= 1'b0;
            sw_reset      <= 1'b0;
            irq_clr_pulse <= 1'b0;

            if (WVALID && WREADY) begin
                case (waddr_offset)
                    REG_CONTROL: begin
                        if (WSTRB[0]) begin
                            start    <= WDATA[0];
                            sw_reset <= WDATA[1];
                        end
                    end
                    REG_TASK_ID: begin
                        for (i = 0; i < DATA_WIDTH/8; i = i + 1)
                            if (WSTRB[i]) task_id_reg[i*8 +: 8] <= WDATA[i*8 +: 8];
                    end
                    REG_IMG_ADDR: begin
                        for (i = 0; i < DATA_WIDTH/8; i = i + 1)
                            if (WSTRB[i]) img_addr_reg[i*8 +: 8] <= WDATA[i*8 +: 8];
                    end
                    REG_IRQ_CLR: begin
                        if (WSTRB[0] && WDATA[0]) irq_clr_pulse <= 1'b1;
                    end
                    default: ; // STATUS, RESULT are read-only
                endcase
            end
        end
    end

    // ==================================================================
    // READ CHANNEL FSM
    // ==================================================================
    localparam R_IDLE = 2'd0,
               R_DATA = 2'd1;

    reg [1:0]            r_state, r_state_next;
    reg [ID_WIDTH-1:0]   arid_capture;
    reg [ADDR_WIDTH-1:0] araddr_ptr;
    reg [2:0]            arsize_capture;
    reg [7:0]             arlen_capture;
    reg [7:0]             rbeat_count;
    wire [5:0]            raddr_offset = araddr_ptr[5:0];
    wire                  r_last_beat  = (rbeat_count == arlen_capture);

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) r_state <= R_IDLE;
        else          r_state <= r_state_next;
    end

    always @(*) begin
        r_state_next = r_state;
        case (r_state)
            R_IDLE: if (ARVALID && ARREADY) r_state_next = R_DATA;
            R_DATA: if (RVALID && RREADY && RLAST) r_state_next = R_IDLE;
            default: r_state_next = R_IDLE;
        endcase
    end

    assign ARREADY = (r_state == R_IDLE);
    assign RVALID  = (r_state == R_DATA);
    assign RID     = arid_capture;
    assign RRESP   = 2'b00; // OKAY
    assign RLAST   = (r_state == R_DATA) && r_last_beat;

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            arid_capture   <= {ID_WIDTH{1'b0}};
            araddr_ptr     <= {ADDR_WIDTH{1'b0}};
            arsize_capture <= 3'b0;
            arlen_capture  <= 8'd0;
            rbeat_count    <= 8'd0;
        end else if (ARVALID && ARREADY) begin
            arid_capture   <= ARID;
            araddr_ptr     <= ARADDR;
            arsize_capture <= ARSIZE;
            arlen_capture  <= ARLEN;
            rbeat_count    <= 8'd0;
        end else if (RVALID && RREADY) begin
            araddr_ptr  <= araddr_ptr + (1'b1 << arsize_capture);
            rbeat_count <= rbeat_count + 1'b1;
        end
    end

    // combinational read-data mux
    reg [DATA_WIDTH-1:0] rdata_mux;
    always @(*) begin
        case (raddr_offset)
            REG_CONTROL:  rdata_mux = {DATA_WIDTH{1'b0}};
            REG_STATUS:   rdata_mux = {{(DATA_WIDTH-2){1'b0}}, done_sticky, busy};
            REG_TASK_ID:  rdata_mux = task_id_reg;
            REG_IMG_ADDR: rdata_mux = img_addr_reg;
            REG_RESULT:   rdata_mux = result_score;
            default:      rdata_mux = {DATA_WIDTH{1'b0}};
        endcase
    end
    assign RDATA = rdata_mux;
    
    always @(posedge ACLK)
    begin
    if (AWVALID && AWREADY)
        $display("AW handshake");

    if (WVALID && WREADY)
        $display("W handshake addr=%h data=%h", awaddr_ptr, WDATA);

    if (start)
        $display("START pulse");
    end

endmodule