// Decode Stage
// This module decodes RISC-V instructions and generates control signals
// for the execution stage. It identifies instruction type, extracts
// register addresses, computes immediate values, and determines which
// functional unit should execute the instruction.

module decode 
import ooo_types::*;
(
    input  logic            clk,
    input  logic            rst,
    input  logic            flush,
    input  logic            freelist_empty,
    input  logic            rs_full,
    input  logic            rob_full,
    input  fetch_packet_t   fetch_packet,    // Instruction and metadata from fetch stage
    input  rvfi_packet_t    fetch_rvfi_packet,        // RVFI packet from fetch stage

    output rvfi_packet_t    decode_rvfi_packet,       // RVFI packet for decode stage
    output decode_packet_t  decode_packet  // Decoded instruction with control signals
);
    // rvfi
    rvfi_packet_t decode_rvfi_packet_next;

    // Internal signals
    instr_t inst;                          // Instruction broken into fields
    decode_packet_t decode_packet_next;    // Combinational decode output
    
    // Immediate values for different instruction formats
    logic [31:0] i_imm, s_imm, u_imm, j_imm, b_imm;

    // Extract instruction from fetch packet
    assign inst.word = fetch_packet.fields.inst;
  
    always_comb begin
        decode_rvfi_packet_next =       fetch_rvfi_packet;
        decode_rvfi_packet_next.rs1_addr =   decode_packet_next.rs1_addr;
        decode_rvfi_packet_next.rs2_addr =   decode_packet_next.rs2_addr;
        decode_rvfi_packet_next.rd_addr  =   decode_packet_next.rd_addr;
    end

    // Optimized: Use continuous assignment for immediate generation (no always block needed)
    assign i_imm = {{20{inst.i_type.imm[11]}}, inst.i_type.imm};
    assign s_imm = {{20{inst.s_type.imm_s_top[11]}}, inst.s_type.imm_s_top, inst.s_type.imm_s_bot};
    assign u_imm = {inst.u_type.imm, 12'b0};
    assign j_imm = {{12{inst.j_type.imm[31]}}, inst.j_type.imm[19:12], inst.j_type.imm[20], inst.j_type.imm[30:21], 1'b0};
    assign b_imm = {{20{inst.b_type.imm_12}}, inst.b_type.imm_11, inst.b_type.imm_10_5, inst.b_type.imm_4_1, 1'b0};

    // Main Decode Logic
    // Decode instruction opcode and generate control signals
    always_comb begin : DECODE
        // Default values - pass through metadata and set safe defaults
        decode_packet_next.valid        = fetch_packet.fields.valid;
        decode_packet_next.inst         = fetch_packet.fields.inst;
        decode_packet_next.pc           = fetch_packet.fields.pc;
        decode_packet_next.rs1_addr     = '0;  // No source register 1
        decode_packet_next.rs2_addr     = '0;  // No source register 2
        decode_packet_next.rd_addr      = '0;  // No destination register
        decode_packet_next.imm          = '0;  // No immediate value
        decode_packet_next.fu_flag      = FU_ALU;  // Default to ALU functional unit
        decode_packet_next.alu_op       = alu_add;  // Default ALU operation
        decode_packet_next.alu_op1_sel  = rs1_out;  // ALU operand 1 from rs1
        decode_packet_next.alu_op2_sel  = rs2_out;  // ALU operand 2 from rs2
        decode_packet_next.cmp_op       = cmp_eq;   // Default comparison operation
        // Only use branch prediction for branch/JAL instructions
        // For non-branch instructions, force to not_taken to avoid spurious flushes
        decode_packet_next.br_pred      = not_taken;  // Will be overridden for branches
        decode_packet_next.pht_counter  = fetch_packet.fields.pht_counter;
        decode_packet_next.pht_index    = fetch_packet.fields.pht_index;
        decode_packet_next.mem_type     = '0;       // Default memory type
        decode_packet_next.mem_op_type  = mem_load; // Default to load

        // Decode based on opcode
        unique case(inst.r_type.opcode)
            // LUI: Load Upper Immediate
            // rd = imm[31:12] << 12
            op_lui: begin
                decode_packet_next.rd_addr      = inst.u_type.rd;
                decode_packet_next.imm          = u_imm;
                decode_packet_next.fu_flag      = FU_ALU;
                decode_packet_next.alu_op       = alu_or;
                decode_packet_next.alu_op1_sel  = rs1_out;
                decode_packet_next.alu_op2_sel  = imm_out;
            end
            
            // AUIPC: Add Upper Immediate to PC
            // rd = pc + (imm[31:12] << 12)
            op_auipc: begin
                decode_packet_next.rd_addr      = inst.u_type.rd;
                decode_packet_next.imm          = u_imm;
                decode_packet_next.fu_flag      = FU_ALU;
                decode_packet_next.alu_op       = alu_add;
                decode_packet_next.alu_op1_sel  = pc_out;   // Use PC as operand 1
                decode_packet_next.alu_op2_sel  = imm_out;
            end

            // JAL: Jump and Link
            // rd = pc + 4, pc = pc + imm (unconditional jump)
            op_jal: begin
                decode_packet_next.rd_addr      = inst.j_type.rd;
                decode_packet_next.imm          = j_imm;
                decode_packet_next.fu_flag      = FU_BR;    // Branch unit handles jumps
                decode_packet_next.cmp_op       = jal;
                decode_packet_next.br_pred      = taken;    // JAL is always taken (unconditional)
            end

            // JALR: Jump and Link Register
            // rd = pc + 4, pc = (rs1 + imm) & ~1
            op_jalr: begin
                decode_packet_next.rd_addr      = inst.i_type.rd;
                decode_packet_next.rs1_addr     = inst.i_type.rs1;  // Base register
                decode_packet_next.imm          = i_imm;
                decode_packet_next.fu_flag      = FU_BR;
                decode_packet_next.cmp_op       = jalr;
                decode_packet_next.br_pred      = taken;    // JALR is always taken (unconditional)
            end

            // Branch Instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU)
            // Conditional branches based on comparison of rs1 and rs2
            op_br: begin
                decode_packet_next.rs1_addr     = inst.b_type.rs1;  // Compare operand 1
                decode_packet_next.rs2_addr     = inst.b_type.rs2;  // Compare operand 2
                decode_packet_next.imm          = b_imm;            // Branch offset
                decode_packet_next.fu_flag      = FU_BR;
                decode_packet_next.br_pred      = fetch_packet.fields.br_pred;  // Use prediction
                
                // Optimized: Aligned for readability
                unique case (inst.b_type.funct3)
                    beq:  decode_packet_next.cmp_op = cmp_eq;
                    bne:  decode_packet_next.cmp_op = cmp_ne;
                    blt:  decode_packet_next.cmp_op = cmp_lt;
                    bge:  decode_packet_next.cmp_op = cmp_ge;
                    bltu: decode_packet_next.cmp_op = cmp_ltu;
                    bgeu: decode_packet_next.cmp_op = cmp_geu;
                    default: decode_packet_next.cmp_op = cmp_eq;
                endcase
            end
            
            // Load Instructions (LB, LH, LW, LBU, LHU)
            // rd = mem[rs1 + imm]
            op_load: begin
                decode_packet_next.rd_addr      = inst.i_type.rd;   // Destination for loaded data
                decode_packet_next.rs1_addr     = inst.i_type.rs1;  // Base address register
                decode_packet_next.imm          = i_imm;            // Address offset
                decode_packet_next.fu_flag      = FU_MEM;           // Memory functional unit
                decode_packet_next.alu_op       = alu_add;          // Calculate address (rs1 + imm)
                decode_packet_next.alu_op1_sel  = rs1_out;
                decode_packet_next.alu_op2_sel  = imm_out;
                decode_packet_next.mem_type     = inst.i_type.funct3;
                decode_packet_next.mem_op_type  = mem_load;
            end
            
            // Store Instructions (SB, SH, SW)
            // mem[rs1 + imm] = rs2
            op_store: begin
                decode_packet_next.rs1_addr     = inst.s_type.rs1;  // Base address register
                decode_packet_next.rs2_addr     = inst.s_type.rs2;  // Data to store
                decode_packet_next.imm          = s_imm;            // Address offset
                decode_packet_next.fu_flag      = FU_MEM;           // Memory functional unit
                decode_packet_next.alu_op       = alu_add;          // Calculate address (rs1 + imm)
                decode_packet_next.alu_op1_sel  = rs1_out;
                decode_packet_next.alu_op2_sel  = imm_out;
                decode_packet_next.mem_type     = inst.s_type.funct3;
                decode_packet_next.mem_op_type  = mem_store;
            end

            // Immediate ALU Operations (ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI)
            // rd = rs1 op imm
            op_imm: begin
                decode_packet_next.rd_addr      = inst.i_type.rd;
                decode_packet_next.rs1_addr     = inst.i_type.rs1;
                decode_packet_next.alu_op1_sel  = rs1_out;
                decode_packet_next.alu_op2_sel  = imm_out;  // Use immediate instead of rs2
                decode_packet_next.imm          = i_imm;
                decode_packet_next.fu_flag      = FU_ALU;

                // Optimized: Remove unnecessary begin-end blocks
                unique case (inst.i_type.funct3)
                    add:  decode_packet_next.alu_op = alu_add;
                    sll:  decode_packet_next.alu_op = alu_sll;
                    slt:  decode_packet_next.cmp_op = cmp_lt;
                    sltu: decode_packet_next.cmp_op = cmp_ltu;
                    axor: decode_packet_next.alu_op = alu_xor;
                    sr:   decode_packet_next.alu_op = inst[30] ? alu_sra : alu_srl;
                    aor:  decode_packet_next.alu_op = alu_or;
                    aand: decode_packet_next.alu_op = alu_and;
                    default: decode_packet_next.alu_op = alu_add;
                endcase
            end

            // Register-Register ALU Operations (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND)
            // rd = rs1 op rs2
            op_reg: begin
                decode_packet_next.rd_addr      = inst.r_type.rd;
                decode_packet_next.rs1_addr     = inst.r_type.rs1;
                decode_packet_next.rs2_addr     = inst.r_type.rs2;
                decode_packet_next.alu_op1_sel  = rs1_out;
                decode_packet_next.alu_op2_sel  = rs2_out;  // Use register instead of immediate
                decode_packet_next.fu_flag      = FU_ALU;

                // RV32M opcodes (funct7 == 7'b0000001) fall through to the
                // base ALU decode below; the toolchain is RV32I-only so they
                // never appear, and any stray encoding lands on alu_add.
                unique case (inst.r_type.funct3)
                    add:  decode_packet_next.alu_op = inst[30] ? alu_sub : alu_add;
                    sll:  decode_packet_next.alu_op = alu_sll;
                    slt:  decode_packet_next.cmp_op = cmp_lt;
                    sltu: decode_packet_next.cmp_op = cmp_ltu;
                    axor: decode_packet_next.alu_op = alu_xor;
                    sr:   decode_packet_next.alu_op = inst[30] ? alu_sra : alu_srl;
                    aor:  decode_packet_next.alu_op = alu_or;
                    aand: decode_packet_next.alu_op = alu_and;
                    default: decode_packet_next.alu_op = alu_add;
                endcase
            end
            // custom-1: fetch_trade rd, imm[2:0] (I-type)
            // Reads parser_output_bram[imm[2:0]] via the dedicated fetch_trade FU.
            // Encoded with opcode=0101011, funct3=0; immediate selects the field.
            op_custom1: begin
                decode_packet_next.rd_addr      = inst.i_type.rd;
                decode_packet_next.rs1_addr     = '0;          // x0 — no operand
                decode_packet_next.imm          = i_imm;       // field index in low bits
                decode_packet_next.fu_flag      = FU_FETCH_TRADE;
            end

            // custom-2: TX primitive (I-type), opcode=1011011
            //   funct3 = 0  → pkt_w  rd, rs1, imm[3:0]  — write 4 octets to TX BRAM[imm]
            //   funct3 = 1  → pkt_s  rd, rs1            — send first rs1 octets
            //   funct3 = 2  → pkt_st rd, imm[2:0]       — read TX status field (no rs1)
            // Pack {funct3[1:0], word_offset[3:0]} into imm[5:0] so dispatch
            // can route without inspecting funct3 directly.
            op_custom2: begin
                decode_packet_next.rd_addr      = inst.i_type.rd;
                decode_packet_next.rs1_addr     = inst.i_type.rs1;
                decode_packet_next.imm          = {26'b0, inst.i_type.funct3[1:0], inst.i_type.imm[3:0]};
                decode_packet_next.fu_flag      = FU_PKT_TX;
            end

            default: begin
                // NOP or unsupported instruction
                decode_packet_next = '0;  // Mark as invalid
            end
        endcase
    end

    // Optimized: Pipeline register with cleaner enable logic
    always_ff @(posedge clk) begin
        if (rst) begin
            decode_packet      <= '0;
            decode_rvfi_packet <= '0;
        end else if (flush) begin
            decode_packet.valid      <= '0;
            decode_rvfi_packet.valid <= '0;
        end else if (!freelist_empty && !rs_full && !rob_full) begin
            decode_packet      <= decode_packet_next;
            decode_rvfi_packet <= decode_rvfi_packet_next;
        end
    end

endmodule : decode