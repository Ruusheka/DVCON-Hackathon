`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_dvcon_top
// Description: Full-system testbench. Drives dvcon_top's AXI4 slave port
//              exactly like VEGA would (write IMG_ADDR, write CONTROL.START,
//              poll STATUS, read RESULT, clear IRQ), with ddr_model supplying
//              real image bytes from an external .bin file on the AXI4
//              master side.
//
// TO USE WITH IMAGE:
//   Change IMG_FILE_PATH below to point at raw RGB .bin file, and
//   IMG_BASE_ADDR / MEM_DEPTH_BYTES he file must contain at least 96 bytes (3 rows x
//   32 pixels) starting at IMG_BASE_ADDR for this single-chunk demo scope.
//////////////////////////////////////////////////////////////////////////////////

module tb_dvcon_top;

    parameter ADDR_WIDTH = 64;
    parameter DATA_WIDTH = 64;
    parameter ID_WIDTH   = 12;

    // ---- EDIT THESE for your own test image ----
    parameter IMG_FILE_PATH    = "C:\Users\mshre\OneDrive - SSN-Institute\Desktop\stage_2b_files\simulation_files\image_rgb.bin";
    //this is the bin file of the images present in this folder we can try with any images 
    parameter [ADDR_WIDTH-1:0] IMG_BASE_ADDR = 64'd0;
    parameter MEM_DEPTH_BYTES  = 1048576;

    reg ACLK;
    reg ARESETN;

    // ---------------- VEGA-side AXI4 signals (dvcon_top's s_* port) ----------------
    reg  [ID_WIDTH-1:0]      AWID;
    reg  [ADDR_WIDTH-1:0]    AWADDR;
    reg  [7:0]               AWLEN;
    reg  [2:0]               AWSIZE;
    reg  [1:0]               AWBURST;
    reg                      AWVALID;
    wire                     AWREADY;

    reg  [DATA_WIDTH-1:0]    WDATA;
    reg  [DATA_WIDTH/8-1:0]  WSTRB;
    reg                      WLAST;
    reg                      WVALID;
    wire                     WREADY;

    wire [ID_WIDTH-1:0]      BID;
    wire [1:0]               BRESP;
    wire                     BVALID;
    reg                      BREADY;

    reg  [ID_WIDTH-1:0]      ARID;
    reg  [ADDR_WIDTH-1:0]    ARADDR;
    reg  [7:0]               ARLEN;
    reg  [2:0]               ARSIZE;
    reg  [1:0]               ARBURST;
    reg                      ARVALID;
    wire                     ARREADY;

    wire [ID_WIDTH-1:0]      RID;
    wire [DATA_WIDTH-1:0]    RDATA;
    wire [1:0]               RRESP;
    wire                     RLAST;
    wire                     RVALID;
    reg                      RREADY;

    // ---------------- DDR-side AXI4 signals (dvcon_top's m_* port <-> ddr_model) ----
    wire [ID_WIDTH-1:0]      d_ARID;
    wire [ADDR_WIDTH-1:0]    d_ARADDR;
    wire [7:0]               d_ARLEN;
    wire [2:0]               d_ARSIZE;
    wire [1:0]               d_ARBURST;
    wire                     d_ARVALID;
    wire                     d_ARREADY;

    wire [ID_WIDTH-1:0]      d_RID;
    wire [DATA_WIDTH-1:0]    d_RDATA;
    wire [1:0]               d_RRESP;
    wire                     d_RLAST;
    wire                     d_RVALID;
    wire                     d_RREADY;

    integer err_count;
    reg [DATA_WIDTH-1:0] rdata_capture;
    integer poll_count;

    // ---------------- DUT ----------------
    dvcon_top #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) dut (
        .ACLK(ACLK), .ARESETN(ARESETN),

        .s_AWID(AWID), .s_AWADDR(AWADDR), .s_AWLEN(AWLEN), .s_AWSIZE(AWSIZE),
        .s_AWBURST(AWBURST), .s_AWVALID(AWVALID), .s_AWREADY(AWREADY),
        .s_WDATA(WDATA), .s_WSTRB(WSTRB), .s_WLAST(WLAST), .s_WVALID(WVALID), .s_WREADY(WREADY),
        .s_BID(BID), .s_BRESP(BRESP), .s_BVALID(BVALID), .s_BREADY(BREADY),
        .s_ARID(ARID), .s_ARADDR(ARADDR), .s_ARLEN(ARLEN), .s_ARSIZE(ARSIZE),
        .s_ARBURST(ARBURST), .s_ARVALID(ARVALID), .s_ARREADY(ARREADY),
        .s_RID(RID), .s_RDATA(RDATA), .s_RRESP(RRESP), .s_RLAST(RLAST),
        .s_RVALID(RVALID), .s_RREADY(RREADY),

        .m_ARID(d_ARID), .m_ARADDR(d_ARADDR), .m_ARLEN(d_ARLEN), .m_ARSIZE(d_ARSIZE),
        .m_ARBURST(d_ARBURST), .m_ARVALID(d_ARVALID), .m_ARREADY(d_ARREADY),
        .m_RID(d_RID), .m_RDATA(d_RDATA), .m_RRESP(d_RRESP), .m_RLAST(d_RLAST),
        .m_RVALID(d_RVALID), .m_RREADY(d_RREADY)
    );

    // ---------------- behavioral, file-backed DDR ----------------
    ddr_model #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH),
        .MEM_DEPTH_BYTES(MEM_DEPTH_BYTES), .IMG_FILE(IMG_FILE_PATH)
    ) u_ddr (
        .ACLK(ACLK), .ARESETN(ARESETN),
        .ARID(d_ARID), .ARADDR(d_ARADDR), .ARLEN(d_ARLEN), .ARSIZE(d_ARSIZE),
        .ARBURST(d_ARBURST), .ARVALID(d_ARVALID), .ARREADY(d_ARREADY),
        .RID(d_RID), .RDATA(d_RDATA), .RRESP(d_RRESP), .RLAST(d_RLAST),
        .RVALID(d_RVALID), .RREADY(d_RREADY)
    );

    // ---------------- 50 MHz clock ----------------
    initial ACLK = 1'b0;
    always #10 ACLK = ~ACLK;

    // ---------------- VEGA-side AXI4 write task ----------------
    task axi_write(
    input [ADDR_WIDTH-1:0] addr,
    input [DATA_WIDTH-1:0] wdata,
    input [DATA_WIDTH/8-1:0] strb
);
begin
    @(posedge ACLK);

    AWID    <= 12'h001;
    AWADDR  <= addr;
    AWLEN   <= 0;
    AWSIZE  <= 3'b011;
    AWBURST <= 2'b01;
    AWVALID <= 1'b1;

    WDATA   <= wdata;
    WSTRB   <= strb;
    WLAST   <= 1'b1;
    WVALID  <= 1'b1;

    BREADY  <= 1'b1;

    wait(AWREADY);
    @(posedge ACLK);
    AWVALID <= 1'b0;

    wait(WREADY);
    @(posedge ACLK);
    WVALID <= 1'b0;
    WLAST  <= 1'b0;

    wait(BVALID);
    @(posedge ACLK);
    BREADY <= 1'b0;
end
endtask

    // ---------------- VEGA-side AXI4 read task ----------------
    task axi_read(input [ADDR_WIDTH-1:0] addr,
                   output [DATA_WIDTH-1:0] rdata_out);
        begin
            @(negedge ACLK);
            ARID    = 12'h002;
            ARADDR  = addr;
            ARLEN   = 8'd0;
            ARSIZE  = 3'b011;
            ARBURST = 2'b01;
            ARVALID = 1'b1;
            RREADY  = 1'b1;

            while (!ARREADY) @(posedge ACLK);
            @(negedge ACLK);
            ARVALID = 1'b0;

            while (!RVALID) @(posedge ACLK);
            rdata_out = RDATA;
            @(negedge ACLK);
            RREADY = 1'b0;
        end
    endtask

    // ---------------- DEBUG MONITOR (temporary - remove once working) ----------------
    
    
    always @(posedge ACLK) begin

    if (AWVALID && AWREADY)
        $display("%0t AW addr=%h", $time, AWADDR);

    if (WVALID && WREADY)
        $display("%0t W data=%h", $time, WDATA);

    if (dut.u_axi4_slave.start)
        $display("%0t START pulse", $time);

    if (dut.u_sequencer.start)
        $display("%0t Sequencer received START", $time);

    if (dut.u_sequencer.rd_start)
        $display("%0t RD_START", $time);

    if (dut.u_axi4_master.ARVALID && dut.u_axi4_master.ARREADY)
        $display("%0t AR issued addr=%h",
                 $time,
                 dut.u_axi4_master.ARADDR);

    if (dut.u_axi4_master.RVALID && dut.u_axi4_master.RREADY)
        $display("%0t Read Beat %h",
                 $time,
                 dut.u_axi4_master.RDATA);

    if (dut.u_axi4_master.rd_done)
        $display("%0t RD_DONE", $time);

    if (dut.u_sequencer.done)
        $display("%0t SEQ_DONE", $time);

end

    // ---------------- main sequence ----------------
    initial begin
        err_count = 0;
        ARESETN   = 1'b0;
        AWVALID=0; WVALID=0; BREADY=0; ARVALID=0; RREADY=0; WLAST=0;

        repeat (5) @(posedge ACLK);
        ARESETN = 1'b1;
        @(posedge ACLK);

        // -------- VEGA: set up the task --------
        axi_write(64'h18, IMG_BASE_ADDR, 8'hFF); // IMG_ADDR register
        axi_write(64'h10, 64'hAAAA_0000_0000_0001, 8'hFF); // TASK_ID (arbitrary demo value)
        axi_write(64'h00, 64'h0000_0000_0000_0001, 8'h01); // CONTROL.START
        $display("[INFO] START written, waiting for accelerator...");

        // -------- VEGA: poll STATUS until DONE --------
        poll_count = 0;
        rdata_capture = 64'd0;
        while (rdata_capture[1] == 1'b0) begin
            axi_read(64'h08, rdata_capture); // STATUS
            poll_count = poll_count + 1;
            if (poll_count > 500) begin
                $display("[FAIL] Timed out polling STATUS - DONE never asserted");
                err_count = err_count + 1;
                $finish;
            end
        end
        $display("[PASS] DONE seen after %0d polls, STATUS = %h", poll_count, rdata_capture);

        // -------- VEGA: read RESULT --------
        axi_read(64'h20, rdata_capture);
        $display("[INFO] RESULT = %h (%0d decimal)", rdata_capture, rdata_capture);
        if (rdata_capture !== 64'd0) begin
            $display("[PASS] RESULT is non-zero - pipeline produced real data");
        end else begin
            $display("[WARN] RESULT is zero - either a genuine zero pooled value, or");
            $display("       DRAIN_CYCLES in dvcon_sequencer fired too early. Check");
            $display("       waveforms (Output_BRAM write timing vs sequencer's read).");
        end

        // -------- VEGA: clear IRQ, confirm DONE deasserts --------
        axi_write(64'h28, 64'h1, 8'h01);
        @(posedge ACLK);
        axi_read(64'h08, rdata_capture);
        if (rdata_capture[1] == 1'b0) begin
            $display("[PASS] DONE cleared after IRQ_CLR");
        end else begin
            $display("[FAIL] DONE still set after IRQ_CLR");
            err_count = err_count + 1;
        end

        // -------- summary --------
        @(posedge ACLK);
        if (err_count == 0)
            $display("\n=== ALL CHECKS PASSED ===");
        else
            $display("\n=== %0d CHECK(S) FAILED ===", err_count);

        $finish;
    end

    // ---------------- watchdog ----------------
    initial begin
        #1000000;
        $display("[TIMEOUT] Simulation did not finish in time");
        $finish;
    end

    // ---------------- waveform dump ----------------
    initial begin
        $dumpfile("tb_dvcon_top.vcd");
        $dumpvars(0, tb_dvcon_top);
    end

endmodule