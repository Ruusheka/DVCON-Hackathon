`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: dvcon_top
// Description: Structural top level. Wires together (unchanged):
//                axi4_slave   - VEGA control/status registers
//                axi4_master  - DDR burst-read engine
//                dvcon_sequencer - new control FSM bridging the two
//                Accelerator_Top - your existing CNN pipeline (unchanged)
//
//              VEGA talks to axi4_slave's AXI4 port; the DDR/MIG controller
//              talks to axi4_master's AXI4 port. Everything in between is
//              wired here.
//////////////////////////////////////////////////////////////////////////////////

module dvcon_top #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 12
)(
    input  wire ACLK,
    input  wire ARESETN,

    // ============ AXI4 slave port - connects to VEGA ============
    input  wire [ID_WIDTH-1:0]      s_AWID,
    input  wire [ADDR_WIDTH-1:0]    s_AWADDR,
    input  wire [7:0]               s_AWLEN,
    input  wire [2:0]               s_AWSIZE,
    input  wire [1:0]               s_AWBURST,
    input  wire                     s_AWVALID,
    output wire                     s_AWREADY,

    input  wire [DATA_WIDTH-1:0]    s_WDATA,
    input  wire [DATA_WIDTH/8-1:0]  s_WSTRB,
    input  wire                     s_WLAST,
    input  wire                     s_WVALID,
    output wire                     s_WREADY,

    output wire [ID_WIDTH-1:0]      s_BID,
    output wire [1:0]               s_BRESP,
    output wire                     s_BVALID,
    input  wire                     s_BREADY,

    input  wire [ID_WIDTH-1:0]      s_ARID,
    input  wire [ADDR_WIDTH-1:0]    s_ARADDR,
    input  wire [7:0]               s_ARLEN,
    input  wire [2:0]               s_ARSIZE,
    input  wire [1:0]               s_ARBURST,
    input  wire                     s_ARVALID,
    output wire                     s_ARREADY,

    output wire [ID_WIDTH-1:0]      s_RID,
    output wire [DATA_WIDTH-1:0]    s_RDATA,
    output wire [1:0]               s_RRESP,
    output wire                     s_RLAST,
    output wire                     s_RVALID,
    input  wire                     s_RREADY,

    // ============ AXI4 master port - connects to DDR/MIG ============
    output wire [ID_WIDTH-1:0]      m_ARID,
    output wire [ADDR_WIDTH-1:0]    m_ARADDR,
    output wire [7:0]               m_ARLEN,
    output wire [2:0]               m_ARSIZE,
    output wire [1:0]               m_ARBURST,
    output wire                     m_ARVALID,
    input  wire                     m_ARREADY,

    input  wire [ID_WIDTH-1:0]      m_RID,
    input  wire [DATA_WIDTH-1:0]    m_RDATA,
    input  wire [1:0]               m_RRESP,
    input  wire                     m_RLAST,
    input  wire                     m_RVALID,
    output wire                     m_RREADY
);

    // bridge active-low async reset (AXI side) <-> active-high sync reset (datapath side)
    wire core_rst = ~ARESETN;

    // -------- axi4_slave <-> sequencer --------
    wire        seq_start;
    wire [DATA_WIDTH-1:0] seq_img_addr;
    wire        seq_busy;
    wire        seq_done;
    wire [DATA_WIDTH-1:0] seq_result;

    // -------- sequencer <-> axi4_master --------
    wire        seq_rd_start;
    wire [ADDR_WIDTH-1:0] seq_rd_base_addr;
    wire [31:0] seq_rd_total_bytes;
    wire        m_rd_busy;
    wire        m_rd_done;

    // -------- axi4_master <-> Accelerator_Top --------
    wire        m_data_valid;
    wire [DATA_WIDTH-1:0] m_data;
    wire        m_data_last; // unused by Accelerator_Top, left dangling on purpose

    // -------- sequencer <-> Accelerator_Top (Output_BRAM read port) --------
    wire [5:0]  ext_read_addr;
    wire [15:0] ext_read_data;

    axi4_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) u_axi4_slave (
        .ACLK(ACLK), .ARESETN(ARESETN),
        .AWID(s_AWID), .AWADDR(s_AWADDR), .AWLEN(s_AWLEN), .AWSIZE(s_AWSIZE),
        .AWBURST(s_AWBURST), .AWVALID(s_AWVALID), .AWREADY(s_AWREADY),
        .WDATA(s_WDATA), .WSTRB(s_WSTRB), .WLAST(s_WLAST), .WVALID(s_WVALID), .WREADY(s_WREADY),
        .BID(s_BID), .BRESP(s_BRESP), .BVALID(s_BVALID), .BREADY(s_BREADY),
        .ARID(s_ARID), .ARADDR(s_ARADDR), .ARLEN(s_ARLEN), .ARSIZE(s_ARSIZE),
        .ARBURST(s_ARBURST), .ARVALID(s_ARVALID), .ARREADY(s_ARREADY),
        .RID(s_RID), .RDATA(s_RDATA), .RRESP(s_RRESP), .RLAST(s_RLAST),
        .RVALID(s_RVALID), .RREADY(s_RREADY),
        .start(seq_start), .sw_reset(), // sw_reset unused in this demo scope
        .task_id_reg(),                 // not used by the single-filter demo
        .img_addr_reg(seq_img_addr),
        .busy(seq_busy), .done(seq_done), .result_score(seq_result)
    );

    axi4_master #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) u_axi4_master (
        .ACLK(ACLK), .ARESETN(ARESETN),
        .ARID(m_ARID), .ARADDR(m_ARADDR), .ARLEN(m_ARLEN),
        .ARSIZE(m_ARSIZE), .ARBURST(m_ARBURST),
        .ARVALID(m_ARVALID), .ARREADY(m_ARREADY),
        .RID(m_RID), .RDATA(m_RDATA), .RRESP(m_RRESP), .RLAST(m_RLAST),
        .RVALID(m_RVALID), .RREADY(m_RREADY),
        .rd_start(seq_rd_start), .rd_base_addr(seq_rd_base_addr),
        .rd_total_bytes(seq_rd_total_bytes),
        .rd_busy(m_rd_busy), .rd_done(m_rd_done),
        .m_data_valid(m_data_valid), .m_data(m_data), .m_data_last(m_data_last),
        .m_data_ready(1'b1) // line buffer has no backpressure - always ready
    );

    dvcon_sequencer u_sequencer (
        .clk(ACLK), .rst(core_rst),
        .start(seq_start), .img_addr_reg(seq_img_addr),
        .busy(seq_busy), .done(seq_done), .result_score(seq_result),
        .rd_start(seq_rd_start), .rd_base_addr(seq_rd_base_addr),
        .rd_total_bytes(seq_rd_total_bytes),
        .rd_busy(m_rd_busy), .rd_done(m_rd_done),
        .external_read_addr(ext_read_addr), .external_read_data(ext_read_data)
    );

    Accelerator_Top u_accel (
        .clk(ACLK), .rst(core_rst),
        .pixel_bus(m_data), .pixel_valid(m_data_valid),
        .external_read_addr(ext_read_addr), .external_read_data(ext_read_data),
        .pool_valid_out(), .final_output() // unused at this level, demo scope
    );

endmodule