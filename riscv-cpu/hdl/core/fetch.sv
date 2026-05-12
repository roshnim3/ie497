module fetch 
import ooo_types::*;
(
    input logic             clk,
    input logic             rst,
    input logic [63:0]      order,
    input logic [1:0]       flush,
    input logic [1:0][31:0] flush_pc, 
    input logic [31:0]      inst_in, // Instruction input from instruction cache
    input logic             cache_resp, // Cache response signal; indicates instruction is ready
    input logic             cache_ready, // Cache can accept a new request
    input logic             freelist_empty, // Indicates if the freelist is empty
    input logic             rob_full, // Indicates if the ROB is full
    input logic             rs_full, // Indicates if the reservation station is full
    
    // Branch predictor inputs
    input br_pred_t         branch_predict,     // Prediction from BP
    input logic [1:0]       pht_counter,        // Counter value from BP
    input logic [7:0]       pht_index,          // PHT index from BP
    input logic  [31:0]     branch_target,  // Target from BTB
    input logic [31:0]      ras_target,          // Target from RAS
    input logic             ras_valid,           // RAS has valid prediction

    output logic [31:0]     pc, // Current program counter; sent to instruction cache and BP
    output logic [31:0]     fetch_inst_out, // Current instruction for early decode (RAS)
    output logic [31:0]     fetch_pc_out,   // PC of instruction coming back (for RAS)
    output logic            fetch_q_full,
    output fetch_packet_t   fetch_packet, // Output fetch packet; from fetch to decode; taken from the queue
    output rvfi_packet_t    fetch_rvfi_packet // Output RVFI packet for verification purposes
);
    logic [31:0] dummy;
    assign dummy = branch_target; // To avoid unused input warnings

    logic [31:0] pc_next; 
    logic full, empty, deq;
    fetch_packet_t fetch_packet_enq;
    fetch_packet_t hold_packet;
    fetch_packet_t queue_packet;
    fetch_stage_t stage_reg;
    logic hold_valid;
    logic queue_enq;
    logic enq_from_hold;
    logic enq_from_resp;
    logic stall;
    logic pc_advance;
    logic resp_ok;
    
    // Branch target calculation signals
    // Note: With pipelined cache + SRAM BP (2 cycle latency), we can't use predictions
    // Branch prediction redirect logic:
    // When BP returns "taken" for the instruction in stage_reg, we need to redirect
    // because we've already sent PC+4 to the cache. Calculate target and invalidate.
    instr_t inst;
    instr_t stage_inst;  // Decode the instruction that came back
    logic [31:0] b_imm, j_imm;
    logic stage_is_jal, stage_is_branch, stage_is_jalr;
    logic [31:0] branch_target_calc;
    logic redirect_on_taken;  // Redirect when taken prediction arrives

    assign fetch_q_full = full;
    assign inst.word = inst_in;
    assign stage_inst.word = inst_in;  // Decode instruction from cache response
    assign fetch_inst_out = inst_in;   // Output for early decode (RAS detection)
    assign fetch_pc_out = stage_reg.pc; // PC of instruction from cache

    // Decode the instruction that came back to check if it's a branch
    assign stage_is_jal    = (stage_inst.r_type.opcode == 7'b1101111); // JAL
    assign stage_is_branch = (stage_inst.r_type.opcode == 7'b1100011); // Branch
    assign stage_is_jalr   = (stage_inst.r_type.opcode == 7'b1100111); // JALR
    
    // Decode immediates for branch target calculation
    assign j_imm = {{12{stage_inst.j_type.imm[31]}}, stage_inst.j_type.imm[19:12], 
                    stage_inst.j_type.imm[20], stage_inst.j_type.imm[30:21], 1'b0};
    assign b_imm = {{20{stage_inst.b_type.imm_12}}, stage_inst.b_type.imm_11, 
                    stage_inst.b_type.imm_10_5, stage_inst.b_type.imm_4_1, 1'b0};
    
    // Calculate branch target using the PC from stage_reg
    assign branch_target_calc = stage_is_jal ? (stage_reg.pc + j_imm) : (stage_reg.pc + b_imm);
    
    // Detect return: JALR with rd == x0
    logic stage_is_return;
    assign stage_is_return = stage_is_jalr && (stage_inst.i_type.rd == 5'd0);
    
    // Redirect when:
    // 1. We have a valid in-flight request
    // 2. Cache responded with an instruction
    // 3a. For JAL: always redirect (unconditional)
    // 3b. For conditional branches: redirect if prediction is "taken"
    // 4. JALR cannot redirect (needs register value)
    assign redirect_on_taken = stage_reg.valid && cache_resp && 
                               ((stage_is_jal) || 
                                (stage_is_branch && stage_reg.branch_predict == taken)) &&
                               !stage_is_jalr;

    // Redirect on return detection: use RAS target if valid
    logic redirect_on_return;
    assign redirect_on_return = stage_reg.valid && cache_resp && stage_is_return && ras_valid;
    
    // PC increment logic: redirect on return, redirect on taken prediction, otherwise +4
    assign pc_next = redirect_on_return ? ras_target : 
                     redirect_on_taken ? branch_target_calc : 
                     (pc + 32'd4);

    // Track the request that is in flight toward the cache.
    // Register the PC and BP prediction information
    // Invalidate when redirecting (the PC+4 request is wrong)
    always_ff @(posedge clk) begin
        if (rst) begin
            stage_reg <= '0;
        end else if (flush[0]) begin
            stage_reg <= '0;
        end else if (flush[1]) begin
            stage_reg <= '0;
        end else if (redirect_on_return || redirect_on_taken) begin
            // Invalidate the stage register when redirecting
            // The cache response for PC+4 should be ignored
            stage_reg <= '0;
        end else if (pc_advance) begin
            stage_reg.valid <= 1'b1;
            stage_reg.pc <= pc;
            stage_reg.pc_next <= pc_next;
            stage_reg.branch_predict <= branch_predict;
            stage_reg.pht_counter <= pht_counter;
            stage_reg.pht_index <= pht_index;
        end
    end
    
    // Fetch packet preparation for enqueue
    // Use the registered prediction values that correspond to this instruction
    // Send prediction through for all instructions - will be filtered later in pipeline
    assign fetch_packet_enq.fields.valid      = resp_ok;
    assign fetch_packet_enq.fields.br_pred    = stage_reg.branch_predict;
    assign fetch_packet_enq.fields.pht_counter = stage_reg.pht_counter;
    assign fetch_packet_enq.fields.pht_index  = stage_reg.pht_index;
    assign fetch_packet_enq.fields.inst       = inst_in;
    assign fetch_packet_enq.fields.pc         = stage_reg.pc;
    assign fetch_packet_enq.fields.pc_next    = stage_reg.pc_next;

    // Hold a cache response if the fetch queue is full. This avoids losing
    // an instruction when full asserts in the same cycle as cache_resp.
    always_ff @(posedge clk) begin
        if (rst || flush[0] || flush[1]) begin
            hold_valid  <= 1'b0;
            hold_packet <= '0;
        end else begin
            if (enq_from_hold) begin
                hold_valid <= 1'b0;
            end else if (resp_ok && full && !hold_valid) begin
                hold_valid  <= 1'b1;
                hold_packet <= fetch_packet_enq;
            end
        end
    end

    // Choose whether we're enqueueing a held packet or a fresh cache response.
    assign enq_from_hold = hold_valid && !full;
    assign resp_ok       = cache_resp && stage_reg.valid;
    assign enq_from_resp = resp_ok && !full && !hold_valid;
    assign queue_enq     = enq_from_hold || enq_from_resp;
    assign queue_packet  = hold_valid ? hold_packet : fetch_packet_enq;
    assign stall         = full || (stage_reg.valid && !(enq_from_hold || resp_ok));
    assign pc_advance    = cache_ready && !full && !stall;

    // Dequeue when downstream stages are ready
    assign deq = !freelist_empty && !rob_full && !rs_full;

    // RVFI packet generation from dequeued fetch packet
    always_comb begin
        fetch_rvfi_packet         = '0;
        fetch_rvfi_packet.valid   = fetch_packet.fields.valid;
        fetch_rvfi_packet.order   = order;
        fetch_rvfi_packet.inst    = fetch_packet.fields.inst;
        fetch_rvfi_packet.pc_rdata = fetch_packet.fields.pc;
        fetch_rvfi_packet.pc_wdata = fetch_packet.fields.pc_next;
    end

    // PC register - redirect on taken prediction, otherwise increment by +4
    // Priority: flush > redirect > normal advance
    always_ff @(posedge clk) begin
        if (rst) begin
            pc <= 32'haaaa_a000;
        end else if (flush[0]) begin
            pc <= flush_pc[0];
        end else if (flush[1]) begin
            pc <= flush_pc[1];
        end else if (redirect_on_return) begin
            pc <= ras_target;
        end else if (redirect_on_taken) begin
            pc <= branch_target_calc;
        end else if (pc_advance) begin
            pc <= pc_next;
        end
    end

    queue #(
        .DATA_WIDTH      ($bits(fetch_packet_t)), // Size of instruction + pc + valid 
        .QUEUE_SIZE      (FETCH_Q_SIZE)
    )    i_queue (
        .clk(clk),
        .rst(rst),
        .flush(|flush),
        .enq(queue_enq),
        .deq(deq),
        .din(queue_packet.raw),
        .dout(fetch_packet.raw),
        .full(full),
        .empty(empty)
    );

endmodule
