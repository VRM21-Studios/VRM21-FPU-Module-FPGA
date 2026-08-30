`timescale 1ns / 1ps
`include "vrm_fpu_constants.vh"

/* ============================================================================
 * MODULE: tb_vrm_fpu_axi
 *
 * DESCRIPTION:
 *   AXI-based verification testbench for the 64-bit VRM Floating-Point Unit.
 *
 *   This testbench verifies the FPU through its external AXI-Lite control
 *   interface and AXI-Stream data interfaces.
 *
 *   The testbench covers:
 *
 *     1. Basic arithmetic
 *        - ADD
 *        - SUB
 *        - MUL
 *        - DIV
 *        - SQRT
 *
 *     2. Conversion and comparison
 *        - Integer to Double
 *        - Double to Integer
 *        - FEQ
 *        - FLT
 *        - FMIN
 *
 *     3. Transcendental functions
 *        - LOG2
 *        - EXP2
 *
 *     4. Fractional transcendental functions
 *        - LOG2(5.0)
 *        - EXP2(1.5)
 *        - LN(e)
 *        - EXP(1.0)
 *
 *     5. Folded mathematical functions
 *        - SIN
 *        - COS
 *        - SIGMOID
 *        - TANH
 *
 * INTERFACE:
 *   AXI-Lite:
 *     Used to configure the FPU operation and funct3 field.
 *
 *   AXI-Stream:
 *     64-bit input and output data paths.
 *
 * NOTES:
 *   - Floating-point operands use IEEE-754 double-precision format.
 *   - The testbench currently performs result observation through $display.
 *   - Expected values are included in the output messages for manual
 *     verification.
 *   - The testbench uses a simple two-word AXI-Stream packet:
 *       word 0 = operand A
 *       word 1 = operand B
 *     with TLAST asserted on operand B.
 * ============================================================================ */

module tb_vrm_fpu_axi;

    // =========================================================================
    // CLOCK AND RESET
    // =========================================================================

    reg clk;
    reg aresetn;

    // 100 MHz clock: 10 ns period.
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Active-low asynchronous AXI reset.
    initial begin
        aresetn = 1'b0;
        #20 aresetn = 1'b1;
    end

    // =========================================================================
    // AXI-LITE MASTER INTERFACE
    // =========================================================================

    reg  [5:0]  s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;

    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;

    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;

    // =========================================================================
    // AXI-STREAM INPUT INTERFACE
    // =========================================================================
    //
    // The FPU data path has been upgraded to 64-bit.
    //
    // A two-operand transaction consists of:
    //
    //   First transfer  -> operand A
    //   Second transfer -> operand B + TLAST
    //
    reg  [63:0] s_axis_tdata;
    reg         s_axis_tvalid;
    reg         s_axis_tlast;
    wire        s_axis_tready;

    // =========================================================================
    // AXI-STREAM OUTPUT INTERFACE
    // =========================================================================

    wire [63:0] m_axis_tdata;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;
    reg         m_axis_tready;

    // =========================================================================
    // IEEE-754 DOUBLE-PRECISION TEST CONSTANTS
    // =========================================================================

    localparam [63:0] FP64_0_0 = 64'h0000000000000000;
    localparam [63:0] FP64_1_0 = 64'h3FF0000000000000;
    localparam [63:0] FP64_1_5 = 64'h3FF8000000000000;
    localparam [63:0] FP64_2_0 = 64'h4000000000000000;
    localparam [63:0] FP64_2_5 = 64'h4004000000000000;
    localparam [63:0] FP64_3_0 = 64'h4008000000000000;
    localparam [63:0] FP64_4_0 = 64'h4010000000000000;
    localparam [63:0] FP64_5_0 = 64'h4014000000000000;
    localparam [63:0] FP64_6_0 = 64'h4018000000000000;
    localparam [63:0] FP64_8_0 = 64'h4020000000000000;

    // Approximate representation of e.
    localparam [63:0] FP64_E =
        64'h4005BF0A8B145769;

    // Integer value 3 stored in the lower 32 bits.
    localparam [63:0] INT32_3 =
        64'h0000000000000003;

    // Expected result for sigmoid(0.0) = 0.5.
    localparam [63:0] FP64_HALF =
        64'h3FE0000000000000;

    // =========================================================================
    // DEVICE UNDER TEST
    // =========================================================================

    vrm_fpu_axi #(
        .C_S_AXI_ADDR_WIDTH(6),
        .C_S_AXI_DATA_WIDTH(32)
    ) dut (
        .aclk          (clk),
        .aresetn       (aresetn),

        // AXI-Lite write channel
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),

        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),

        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),

        // AXI-Lite read channel is not used by this testbench.
        .s_axi_araddr  (6'd0),
        .s_axi_arvalid (1'b0),
        .s_axi_arready (),
        .s_axi_rdata   (),
        .s_axi_rresp   (),
        .s_axi_rvalid  (),
        .s_axi_rready  (1'b0),

        // AXI-Stream input
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tready (s_axis_tready),

        // AXI-Stream output
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tlast  (m_axis_tlast),
        .m_axis_tready (m_axis_tready)
    );

    // =========================================================================
    // TEST RESULT REGISTER
    // =========================================================================

    reg [63:0] res = 64'd0;

    // =========================================================================
    // AXI-LITE WRITE TASK
    // =========================================================================
    //
    // Performs a single AXI-Lite write transaction.
    //
    // The current FPU configuration uses:
    //
    //   Address 8  -> FPU operation selector
    //   Address 12 -> funct3 selector
    //
    task axi_write;
        input [5:0]  addr;
        input [31:0] data;

        begin
            @(posedge clk);

            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;

            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1'b1;
            s_axi_wstrb   <= 4'hF;

            s_axi_bready  <= 1'b1;

            // Wait until both address and data channels are accepted.
            wait (s_axi_awready && s_axi_wready);

            @(posedge clk);

            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            // Wait for the write response.
            wait (s_axi_bvalid);

            @(posedge clk);

            s_axi_bready <= 1'b0;
        end
    endtask

    // =========================================================================
    // FPU TRANSACTION TASK
    // =========================================================================
    //
    // Configures the requested FPU operation and sends two 64-bit operands
    // through the AXI-Stream input interface.
    //
    // Packet format:
    //
    //   Transfer 1:
    //       tdata = operand A
    //       tlast = 0
    //
    //   Transfer 2:
    //       tdata = operand B
    //       tlast = 1
    //
    // The task then waits for the FPU result on the AXI-Stream output.
    //
    task apply;
        input [3:0]  op;
        input [2:0]  f3;
        input [63:0] a;
        input [63:0] b;

        begin
            // -----------------------------------------------------------------
            // 1. Configure the FPU operation.
            // -----------------------------------------------------------------

            axi_write(
                6'd8,
                {28'd0, op}
            );

            axi_write(
                6'd12,
                {29'd0, f3}
            );

            // -----------------------------------------------------------------
            // 2. Send operand A.
            // -----------------------------------------------------------------

            @(posedge clk);

            s_axis_tdata  <= a;
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= 1'b0;

            // -----------------------------------------------------------------
            // 3. Send operand B and mark the end of the packet.
            // -----------------------------------------------------------------

            @(posedge clk);

            s_axis_tdata <= b;
            s_axis_tlast <= 1'b1;

            // -----------------------------------------------------------------
            // 4. End the input transaction.
            // -----------------------------------------------------------------

            @(posedge clk);

            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;

            // -----------------------------------------------------------------
            // 5. Wait for and capture the output result.
            // -----------------------------------------------------------------

            m_axis_tready <= 1'b1;

            wait (m_axis_tvalid);

            @(posedge clk);

            res = m_axis_tdata;

            m_axis_tready <= 1'b0;
        end
    endtask

    // =========================================================================
    // TEST SEQUENCE
    // =========================================================================

    initial begin

        // ---------------------------------------------------------------------
        // Simulation waveform dump.
        // ---------------------------------------------------------------------

        $dumpfile("dump.vcd");
        $dumpvars(0, tb_vrm_fpu_axi);

        // ---------------------------------------------------------------------
        // Initialize all testbench signals.
        // ---------------------------------------------------------------------

        s_axi_awaddr  = 6'd0;
        s_axi_awvalid = 1'b0;

        s_axi_wdata   = 32'd0;
        s_axi_wvalid  = 1'b0;
        s_axi_wstrb   = 4'd0;

        s_axi_bready  = 1'b0;

        s_axis_tdata  = 64'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        m_axis_tready = 1'b0;

        // Allow reset to complete and the DUT to initialize.
        #100;

        // =====================================================================
        // TEST HEADER
        // =====================================================================

        $display("=================================================");
        $display("=== VRM FPU AXI HARDWARE VERIFICATION (FP64) ===");
        $display("=================================================");

        // =====================================================================
        // [1] BASIC ARITHMETIC
        // =====================================================================

        $display("");
        $display("[1] BASIC ARITHMETIC");

        // ADD: 1.5 + 2.5 = 4.0
        apply(
            4'd0,
            3'd0,
            FP64_1_5,
            FP64_2_5
        );
        $display(
            "ADD  (1.5 + 2.5) : %h",
            res
        );

        // SUB: 5.0 - 3.0 = 2.0
        apply(
            4'd1,
            3'd0,
            FP64_5_0,
            FP64_3_0
        );
        $display(
            "SUB  (5.0 - 3.0) : %h",
            res
        );

        // MUL: 2.0 * 3.0 = 6.0
        apply(
            4'd2,
            3'd0,
            FP64_2_0,
            FP64_3_0
        );
        $display(
            "MUL  (2.0 * 3.0) : %h",
            res
        );

        // DIV: 6.0 / 2.0 = 3.0
        apply(
            4'd3,
            3'd0,
            FP64_6_0,
            FP64_2_0
        );
        $display(
            "DIV  (6.0 / 2.0) : %h",
            res
        );

        // SQRT: sqrt(4.0) = 2.0
        apply(
            4'd4,
            3'd0,
            FP64_4_0,
            64'd0
        );
        $display(
            "SQRT (sqrt(4.0)) : %h",
            res
        );

        // =====================================================================
        // [2] CONVERSION AND COMPARISON
        // =====================================================================

        $display("");
        $display("[2] CONVERSION AND COMPARISON");

        // Integer-to-double conversion: 3 -> 3.0
        apply(
            4'd5,
            3'd0,
            INT32_3,
            64'd0
        );
        $display(
            "I2F  (Integer 3)     : %h",
            res
        );

        // Double-to-integer conversion: 3.0 -> 3
        apply(
            4'd6,
            3'd0,
            FP64_3_0,
            64'd0
        );
        $display(
            "F2I  (Double 3.0)    : %h",
            res
        );

        // FEQ: 2.0 == 2.0 -> 1
        apply(
            4'd7,
            3'd0,
            FP64_2_0,
            FP64_2_0
        );
        $display(
            "FEQ  (2.0 == 2.0)   : %h (Expected: 1)",
            res
        );

        // FLT: 2.0 < 3.0 -> 1
        apply(
            4'd7,
            3'd1,
            FP64_2_0,
            FP64_3_0
        );
        $display(
            "FLT  (2.0 < 3.0)    : %h (Expected: 1)",
            res
        );

        // FMIN: min(2.0, 3.0) = 2.0
        apply(
            4'd7,
            3'd3,
            FP64_2_0,
            FP64_3_0
        );
        $display(
            "FMIN (2.0, 3.0)     : %h",
            res
        );

        // =====================================================================
        // [3] TRANSCENDENTAL FUNCTIONS - INTEGER TEST CASES
        // =====================================================================

        $display("");
        $display("[3] TRANSCENDENTAL FUNCTIONS - INTEGER TEST CASES");

        // LOG2(8.0) = 3.0
        apply(
            4'd8,
            3'd0,
            FP64_8_0,
            64'd0
        );
        $display(
            "LOG2 (8.0)          : %h (Expected: 4008000000000000 = 3.0)",
            res
        );

        // EXP2(3.0) = 8.0
        apply(
            4'd8,
            3'd2,
            FP64_3_0,
            64'd0
        );
        $display(
            "EXP2 (3.0)          : %h (Expected: 4020000000000000 = 8.0)",
            res
        );

        // =====================================================================
        // [4] TRANSCENDENTAL FUNCTIONS - FRACTIONAL TEST CASES
        // =====================================================================

        $display("");
        $display("[4] TRANSCENDENTAL FUNCTIONS - FRACTIONAL TEST CASES");

        // ---------------------------------------------------------------------
        // LOG2(5.0)
        //
        // Expected:
        //     log2(5.0) = 2.32192809...
        //
        // Reference hexadecimal value:
        //     4002931168051E83
        // ---------------------------------------------------------------------

        apply(
            4'd8,
            3'd0,
            FP64_5_0,
            64'd0
        );
        $display(
            "LOG2 (5.0)          : %h (Expected: approximately 40029311...)",
            res
        );

        // ---------------------------------------------------------------------
        // EXP2(1.5)
        //
        // Expected:
        //     2^1.5 = sqrt(8) = 2.82842712...
        //
        // Reference hexadecimal value:
        //     4006A09E667F3BCC
        // ---------------------------------------------------------------------

        apply(
            4'd8,
            3'd2,
            FP64_1_5,
            64'd0
        );
        $display(
            "EXP2 (1.5)          : %h (Expected: approximately 4006A09E...)",
            res
        );

        // ---------------------------------------------------------------------
        // LN(e)
        //
        // Expected:
        //     ln(e) = 1.0
        // ---------------------------------------------------------------------

        apply(
            4'd8,
            3'd1,
            FP64_E,
            64'd0
        );
        $display(
            "LN   (e)            : %h (Expected: 3FF0000000000000 = 1.0)",
            res
        );

        // ---------------------------------------------------------------------
        // EXP(1.0)
        //
        // Expected:
        //     exp(1.0) = e = 2.71828...
        //
        // Reference hexadecimal value:
        //     4005BF0A8B145769
        // ---------------------------------------------------------------------

        apply(
            4'd8,
            3'd3,
            FP64_1_0,
            64'd0
        );
        $display(
            "EXP  (1.0)          : %h (Expected: 4005BF0A8B145769 = e)",
            res
        );

        // =====================================================================
        // [5] FOLDED ARCHITECTURE TEST - SIN AND COS
        // =====================================================================

        $display("");
        $display("[5] FOLDED ARCHITECTURE TEST - SIN AND COS");

        // ---------------------------------------------------------------------
        // SIN(0.0) = 0.0
        // ---------------------------------------------------------------------

        apply(
            4'd8,
            3'd6,
            FP64_0_0,
            64'd0
        );
        $display(
            "SIN  (0.0)          : %h (Expected: 0000000000000000 = 0.0)",
            res
        );

        // ---------------------------------------------------------------------
        // COS(0.0) = 1.0
        // ---------------------------------------------------------------------

        apply(
            4'd8,
            3'd7,
            FP64_0_0,
            64'd0
        );
        $display(
            "COS  (0.0)          : %h (Expected: 3FF0000000000000 = 1.0)",
            res
        );

        // =====================================================================
        // [6] ACTIVATION FUNCTION TEST - SIGMOID AND TANH
        // =====================================================================

        $display("");
        $display("[6] ACTIVATION FUNCTION TEST - SIGMOID AND TANH");

        // ---------------------------------------------------------------------
        // SIGMOID(0.0)
        //
        // sigmoid(x) = 1 / (1 + exp(-x))
        //
        // Therefore:
        //
        //     sigmoid(0) = 0.5
        //
        // Expected:
        //     3FE0000000000000
        // ---------------------------------------------------------------------

        apply(
            4'd8,
            3'd4,
            FP64_0_0,
            64'd0
        );
        $display(
            "SIGMOID (0.0)      : %h (Expected: 3FE0000000000000 = 0.5)",
            res
        );

        // ---------------------------------------------------------------------
        // TANH(0.0)
        //
        // tanh(x) = (exp(2x) - 1) / (exp(2x) + 1)
        //
        // Therefore:
        //
        //     tanh(0) = 0.0
        //
        // Expected:
        //     0000000000000000
        // ---------------------------------------------------------------------

        apply(
            4'd8,
            3'd5,
            FP64_0_0,
            64'd0
        );
        $display(
            "TANH    (0.0)      : %h (Expected: 0000000000000000 = 0.0)",
            res
        );

        // =====================================================================
        // SIMULATION FINISHED
        // =====================================================================

        $display("");
        $display("=================================================");
        $display("=== SIMULATION FINISHED =========================");
        $display("=================================================");

        #100;
        $finish;
    end

endmodule
