`timescale 1ns / 1ps

// ============================================================================
// MODULE: vrm_fpu_axi
// DESCRIPTION:
// AXI4-Lite and AXI4-Stream wrapper for the VRM FPU.
//
// The AXI4-Lite interface provides control and status register access,
// while the AXI4-Stream interfaces provide 64-bit operand input and
// result output.
//
// Input operands are assembled as two consecutive 64-bit words:
// - First word  : Operand A
// - Second word : Operand B
//
// The wrapper uses vrm_fifo for input and output buffering.
//
// FEATURES:
// - AXI4-Lite control interface
// - AXI4-Stream 64-bit input interface
// - AXI4-Stream 64-bit output interface
// - 64-bit input FIFO
// - 64-bit output FIFO
// - Two-word operand packet assembly
// - Configurable FPU operation and funct3 control
// - Software-controlled soft reset
// - FPU status reporting
//
// DEPENDENCIES:
// - vrm_fpu
// - vrm_fifo
// ============================================================================

module vrm_fpu_axi #
(
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer C_S_AXI_DATA_WIDTH = 32
)
(
    // =========================================================================
    // AXI4-Lite Control Interface
    // =========================================================================
    input  wire                          aclk,
    input  wire                          aresetn,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                          s_axi_awvalid,
    output reg                           s_axi_awready,
    input  wire [31:0]                   s_axi_wdata,
    input  wire [3:0]                    s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output reg                           s_axi_wready,
    output reg [1:0]                     s_axi_bresp,
    output reg                           s_axi_bvalid,
    input  wire                          s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                          s_axi_arvalid,
    output reg                           s_axi_arready,
    output reg [31:0]                    s_axi_rdata,
    output reg [1:0]                     s_axi_rresp,
    output reg                           s_axi_rvalid,
    input  wire                          s_axi_rready,

    // =========================================================================
    // AXI4-Stream Input
    //
    // Each 64-bit word represents one FPU operand.
    // Two consecutive words are assembled into an FPU operation:
    //   Word 0 -> Operand A
    //   Word 1 -> Operand B
    // =========================================================================
    input  wire [63:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,

    // =========================================================================
    // AXI4-Stream Output
    //
    // The 64-bit FPU result is forwarded through the output FIFO.
    // =========================================================================
    output wire [63:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready
);

    // =========================================================================
    // 1. Control and Status Registers
    // =========================================================================
    reg [31:0] reg_ctrl;
    reg [31:0] reg_status;
    reg [3:0]  reg_fpu_op;
    reg [2:0]  reg_funct3;

    // Soft reset is controlled by CTRL[1].
    // The effective reset is asserted when either AXI reset or soft reset
    // is active.
    wire soft_reset = reg_ctrl[1];
    wire axi_rstn = aresetn && !soft_reset;

    // =========================================================================
    // 2. Input FIFO
    //
    // The reusable vrm_fifo module provides buffering between the external
    // AXI4-Stream input and the packet assembler.
    // =========================================================================
    wire [63:0] in_fifo_data;
    wire        in_fifo_valid;
    wire        in_fifo_ready;
    wire        in_fifo_almost_full;

    vrm_fifo #(.DATA_WIDTH(64), .FIFO_DEPTH(1024)) input_fifo (
        .aclk               (aclk),
        .aresetn            (axi_rstn),
        .s_axis_tdata       (s_axis_tdata),
        .s_axis_tlast       (s_axis_tlast),
        .s_axis_tvalid      (s_axis_tvalid),
        .s_axis_tready      (s_axis_tready),
        .s_axis_almost_full (in_fifo_almost_full),
        .m_axis_tdata       (in_fifo_data),
        .m_axis_tlast       (),                     // TLAST is not used
        .m_axis_tvalid     (in_fifo_valid),
        .m_axis_tready      (in_fifo_ready)
    );

    // The packet assembler continuously accepts data from the input FIFO.
    assign in_fifo_ready = 1'b1;

    // =========================================================================
    // 3. Packet Assembler
    //
    // Two consecutive 64-bit words are collected before triggering the FPU.
    //
    //   packet_count = 0 -> Waiting for Operand A
    //   packet_count = 1 -> Waiting for Operand B
    //
    // fpu_valid is asserted for one clock cycle when both operands are ready.
    // =========================================================================
    reg        packet_count;
    reg [63:0] op_a, op_b;
    reg        fpu_valid;

    always @(posedge aclk) begin
        if (!axi_rstn) begin
            packet_count <= 1'b0;
            fpu_valid    <= 1'b0;
            op_a         <= 64'd0;
            op_b         <= 64'd0;
        end else begin
            fpu_valid <= 1'b0;   // One-cycle trigger pulse

            if (in_fifo_valid) begin
                case (packet_count)
                    1'b0: begin
                        op_a         <= in_fifo_data;
                        packet_count <= 1'b1;
                    end

                    1'b1: begin
                        op_b         <= in_fifo_data;
                        packet_count <= 1'b0;
                        fpu_valid    <= 1'b1;   // Both operands are available
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // 4. FPU Core
    //
    // The selected operation is configured through the AXI4-Lite control
    // registers. The FPU core receives two 64-bit operands and generates
    // a 64-bit result together with a valid indication.
    // =========================================================================
    wire [63:0] fpu_result;
    wire        fpu_result_valid;

    vrm_fpu u_fpu (
        .clk       (aclk),
        .rstn      (axi_rstn),
        .valid_in  (fpu_valid),
        .fpu_op    (reg_fpu_op),
        .funct3    (reg_funct3),
        .op_a      (op_a),
        .op_b      (op_b),
        .result_out(fpu_result),
        .valid_out (fpu_result_valid)
    );

    // =========================================================================
    // 5. Output FIFO
    //
    // FPU results are buffered before being exposed through the external
    // AXI4-Stream output interface.
    // =========================================================================
    vrm_fifo #(.DATA_WIDTH(64), .FIFO_DEPTH(1024)) output_fifo (
        .aclk               (aclk),
        .aresetn            (axi_rstn),
        .s_axis_tdata       (fpu_result),
        .s_axis_tlast       (1'b1),
        .s_axis_tvalid      (fpu_result_valid),
        .s_axis_tready      (),
        .s_axis_almost_full (),
        .m_axis_tdata       (m_axis_tdata),
        .m_axis_tlast       (m_axis_tlast),
        .m_axis_tvalid      (m_axis_tvalid),
        .m_axis_tready      (m_axis_tready)
    );

    // =========================================================================
    // 6. Status Register
    //
    // STATUS bits:
    //   [0] = Packet assembler is waiting for Operand B
    //   [1] = Input FIFO is almost full
    //   [2] = Output FIFO contains valid output data
    // =========================================================================
    always @(*) begin
        reg_status = 32'd0;
        reg_status[0] = (packet_count != 1'b0);
        reg_status[1] = in_fifo_almost_full;
        reg_status[2] = m_axis_tvalid;
    end

    // =========================================================================
    // 7. AXI4-Lite Write Interface
    //
    // Register map:
    //   0x00 -> CTRL
    //   0x08 -> FPU Operation
    //   0x0C -> FUNCT3
    // =========================================================================
    always @(posedge aclk) begin
        if (!axi_rstn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            reg_ctrl      <= 0;
            reg_fpu_op    <= 0;
            reg_funct3    <= 0;
        end else begin
            s_axi_awready <= s_axi_awvalid && !s_axi_awready;
            s_axi_wready  <= s_axi_wvalid && !s_axi_wready;

            if (s_axi_awvalid && s_axi_awready &&
                s_axi_wvalid  && s_axi_wready) begin

                s_axi_bvalid <= 1'b1;

                case (s_axi_awaddr[5:2])
                    4'd0: reg_ctrl   <= s_axi_wdata;
                    4'd2: reg_fpu_op <= s_axi_wdata[3:0];
                    4'd3: reg_funct3 <= s_axi_wdata[2:0];
                endcase

            end else if (s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 8. AXI4-Lite Read Interface
    //
    // Register map:
    //   0x00 -> CTRL
    //   0x04 -> STATUS
    //   0x08 -> FPU Operation
    //   0x0C -> FUNCT3
    // =========================================================================
    always @(posedge aclk) begin
        if (!axi_rstn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
        end else begin
            s_axi_arready <= s_axi_arvalid && !s_axi_arready;

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;

                case (s_axi_araddr[5:2])
                    4'd0: s_axi_rdata <= reg_ctrl;
                    4'd1: s_axi_rdata <= reg_status;
                    4'd2: s_axi_rdata <= {28'd0, reg_fpu_op};
                    4'd3: s_axi_rdata <= {29'd0, reg_funct3};
                    default: s_axi_rdata <= 32'h0;
                endcase

            end else if (s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // AXI4-Lite responses are always OKAY.
    initial begin
        s_axi_bresp = 2'b00;
        s_axi_rresp = 2'b00;
    end

endmodule`timescale 1ns / 1ps

module vrm_fpu_axi #
(
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer C_S_AXI_DATA_WIDTH = 32
)
(
    // =========================================================================
    // AXI4-Lite Control Interface
    // =========================================================================
    input  wire                          aclk,
    input  wire                          aresetn,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                          s_axi_awvalid,
    output reg                           s_axi_awready,
    input  wire [31:0]                   s_axi_wdata,
    input  wire [3:0]                    s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output reg                           s_axi_wready,
    output reg [1:0]                     s_axi_bresp,
    output reg                           s_axi_bvalid,
    input  wire                          s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                          s_axi_arvalid,
    output reg                           s_axi_arready,
    output reg [31:0]                    s_axi_rdata,
    output reg [1:0]                     s_axi_rresp,
    output reg                           s_axi_rvalid,
    input  wire                          s_axi_rready,

    // =========================================================================
    // AXI4-Stream Input
    //
    // Each 64-bit word represents one FPU operand.
    // Two consecutive words are assembled into an FPU operation:
    //   Word 0 -> Operand A
    //   Word 1 -> Operand B
    // =========================================================================
    input  wire [63:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,

    // =========================================================================
    // AXI4-Stream Output
    //
    // The 64-bit FPU result is forwarded through the output FIFO.
    // =========================================================================
    output wire [63:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready
);

    // =========================================================================
    // 1. Control and Status Registers
    // =========================================================================
    reg [31:0] reg_ctrl;
    reg [31:0] reg_status;
    reg [3:0]  reg_fpu_op;
    reg [2:0]  reg_funct3;

    // Soft reset is controlled by CTRL[1].
    // The effective reset is asserted when either AXI reset or soft reset
    // is active.
    wire soft_reset = reg_ctrl[1];
    wire axi_rstn = aresetn && !soft_reset;

    // =========================================================================
    // 2. Input FIFO
    //
    // The reusable vrm_fifo module provides buffering between the external
    // AXI4-Stream input and the packet assembler.
    // =========================================================================
    wire [63:0] in_fifo_data;
    wire        in_fifo_valid;
    wire        in_fifo_ready;
    wire        in_fifo_almost_full;

    vrm_fifo #(.DATA_WIDTH(64), .FIFO_DEPTH(1024)) input_fifo (
        .aclk               (aclk),
        .aresetn            (axi_rstn),
        .s_axis_tdata       (s_axis_tdata),
        .s_axis_tlast       (s_axis_tlast),
        .s_axis_tvalid      (s_axis_tvalid),
        .s_axis_tready      (s_axis_tready),
        .s_axis_almost_full (in_fifo_almost_full),
        .m_axis_tdata       (in_fifo_data),
        .m_axis_tlast       (),                     // TLAST is not used
        .m_axis_tvalid     (in_fifo_valid),
        .m_axis_tready      (in_fifo_ready)
    );

    // The packet assembler continuously accepts data from the input FIFO.
    assign in_fifo_ready = 1'b1;

    // =========================================================================
    // 3. Packet Assembler
    //
    // Two consecutive 64-bit words are collected before triggering the FPU.
    //
    //   packet_count = 0 -> Waiting for Operand A
    //   packet_count = 1 -> Waiting for Operand B
    //
    // fpu_valid is asserted for one clock cycle when both operands are ready.
    // =========================================================================
    reg        packet_count;
    reg [63:0] op_a, op_b;
    reg        fpu_valid;

    always @(posedge aclk) begin
        if (!axi_rstn) begin
            packet_count <= 1'b0;
            fpu_valid    <= 1'b0;
            op_a         <= 64'd0;
            op_b         <= 64'd0;
        end else begin
            fpu_valid <= 1'b0;   // One-cycle trigger pulse

            if (in_fifo_valid) begin
                case (packet_count)
                    1'b0: begin
                        op_a         <= in_fifo_data;
                        packet_count <= 1'b1;
                    end

                    1'b1: begin
                        op_b         <= in_fifo_data;
                        packet_count <= 1'b0;
                        fpu_valid    <= 1'b1;   // Both operands are available
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // 4. FPU Core
    //
    // The selected operation is configured through the AXI4-Lite control
    // registers. The FPU core receives two 64-bit operands and generates
    // a 64-bit result together with a valid indication.
    // =========================================================================
    wire [63:0] fpu_result;
    wire        fpu_result_valid;

    vrm_fpu u_fpu (
        .clk       (aclk),
        .rstn      (axi_rstn),
        .valid_in  (fpu_valid),
        .fpu_op    (reg_fpu_op),
        .funct3    (reg_funct3),
        .op_a      (op_a),
        .op_b      (op_b),
        .result_out(fpu_result),
        .valid_out (fpu_result_valid)
    );

    // =========================================================================
    // 5. Output FIFO
    //
    // FPU results are buffered before being exposed through the external
    // AXI4-Stream output interface.
    // =========================================================================
    vrm_fifo #(.DATA_WIDTH(64), .FIFO_DEPTH(1024)) output_fifo (
        .aclk               (aclk),
        .aresetn            (axi_rstn),
        .s_axis_tdata       (fpu_result),
        .s_axis_tlast       (1'b1),
        .s_axis_tvalid      (fpu_result_valid),
        .s_axis_tready      (),
        .s_axis_almost_full (),
        .m_axis_tdata       (m_axis_tdata),
        .m_axis_tlast       (m_axis_tlast),
        .m_axis_tvalid      (m_axis_tvalid),
        .m_axis_tready      (m_axis_tready)
    );

    // =========================================================================
    // 6. Status Register
    //
    // STATUS bits:
    //   [0] = Packet assembler is waiting for Operand B
    //   [1] = Input FIFO is almost full
    //   [2] = Output FIFO contains valid output data
    // =========================================================================
    always @(*) begin
        reg_status = 32'd0;
        reg_status[0] = (packet_count != 1'b0);
        reg_status[1] = in_fifo_almost_full;
        reg_status[2] = m_axis_tvalid;
    end

    // =========================================================================
    // 7. AXI4-Lite Write Interface
    //
    // Register map:
    //   0x00 -> CTRL
    //   0x08 -> FPU Operation
    //   0x0C -> FUNCT3
    // =========================================================================
    always @(posedge aclk) begin
        if (!axi_rstn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            reg_ctrl      <= 0;
            reg_fpu_op    <= 0;
            reg_funct3    <= 0;
        end else begin
            s_axi_awready <= s_axi_awvalid && !s_axi_awready;
            s_axi_wready  <= s_axi_wvalid && !s_axi_wready;

            if (s_axi_awvalid && s_axi_awready &&
                s_axi_wvalid  && s_axi_wready) begin

                s_axi_bvalid <= 1'b1;

                case (s_axi_awaddr[5:2])
                    4'd0: reg_ctrl   <= s_axi_wdata;
                    4'd2: reg_fpu_op <= s_axi_wdata[3:0];
                    4'd3: reg_funct3 <= s_axi_wdata[2:0];
                endcase

            end else if (s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 8. AXI4-Lite Read Interface
    //
    // Register map:
    //   0x00 -> CTRL
    //   0x04 -> STATUS
    //   0x08 -> FPU Operation
    //   0x0C -> FUNCT3
    // =========================================================================
    always @(posedge aclk) begin
        if (!axi_rstn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
        end else begin
            s_axi_arready <= s_axi_arvalid && !s_axi_arready;

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;

                case (s_axi_araddr[5:2])
                    4'd0: s_axi_rdata <= reg_ctrl;
                    4'd1: s_axi_rdata <= reg_status;
                    4'd2: s_axi_rdata <= {28'd0, reg_fpu_op};
                    4'd3: s_axi_rdata <= {29'd0, reg_funct3};
                    default: s_axi_rdata <= 32'h0;
                endcase

            end else if (s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // AXI4-Lite responses are always OKAY.
    initial begin
        s_axi_bresp = 2'b00;
        s_axi_rresp = 2'b00;
    end

endmodule
