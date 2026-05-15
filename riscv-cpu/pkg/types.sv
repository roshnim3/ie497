package ooo_types;

    // TODO: Wherevere there is DEBUG_ONLY will be removed later, when CP3 works

    localparam ROB_SIZE     = 32; // Keep ROB_SIZE as power of 2
    localparam ALU_RS_SIZE  = 16; // Keep ALU_RS_SIZE as power of 2
    localparam MUL_RS_SIZE  = 8;  // Keep MUL_RS_SIZE as power of 2
    localparam DIV_RS_SIZE  = 4;  // Keep DIV_RS_SIZE as power of 2
    localparam BR_RS_SIZE   = 8;  // Keep BR_RS_SIZE as power of 2
    localparam MEM_RS_SIZE  = 16; // Keep MEM_RS_SIZE as power of 2
    localparam FT_RS_SIZE   = 4;  // fetch_trade RS depth (power of 2)
    localparam PT_RS_SIZE   = 4;  // pkt_tx RS depth (power of 2)
    localparam LSQ_SIZE     = 8;  // Keep LSQ_SIZE as power of 2
    localparam FETCH_Q_SIZE = 8;  // Keep FETCH_QUEUE_SIZE as power of 2

    localparam mult_a_width = 33;
    localparam mult_b_width = 33;
    localparam mult_num_stages = 6;
    localparam mult_stall_mode = 0;
    localparam mult_rst_mode = 2;
    localparam mult_op_iso_mode = 2;

    localparam div_a_width = 33;
    localparam div_b_width = 33;
    localparam div_tc_mode = 1;
    localparam div_num_cyc = 20;
    localparam div_rst_mode = 1;
    localparam div_input_mode = 1;
    localparam div_output_mode = 1;
    localparam div_early_start = 0;

    // RVFI packet structure for RISC-V Formal Verification Interface
    typedef struct packed {
        logic         valid;
        logic [63:0]  order;
        logic [31:0]  inst;
        logic [4:0]   rs1_addr;
        logic [4:0]   rs2_addr;
        logic [31:0]  rs1_rdata;
        logic [31:0]  rs2_rdata;
        logic [4:0]   rd_addr;
        logic [31:0]  rd_wdata;
        logic [31:0]  pc_rdata;
        logic [31:0]  pc_wdata;
        logic [31:0]  mem_addr;
        logic [3:0]  mem_rmask;
        logic [3:0]  mem_wmask;
        logic [31:0]  mem_rdata;
        logic [31:0]  mem_wdata;
    } rvfi_packet_t;

    // RISC-V Opcodes
    typedef enum logic [6:0] {
        op_lui       = 7'b0110111, // load upper imemediate (U type)
        op_auipc     = 7'b0010111, // add upper imemediate PC (U type)
        op_jal       = 7'b1101111, // jump and link (J type)
        op_jalr      = 7'b1100111, // jump and link register (I type)
        op_br        = 7'b1100011, // branch (B type)
        op_load      = 7'b0000011, // load (I type)
        op_store     = 7'b0100011, // store (S type)
        op_imm       = 7'b0010011, // arith ops with register/imemediate operands (I type)
        op_reg       = 7'b0110011, // arith ops with register operands (R type)
        op_custom1   = 7'b0101011, // fetch_trade rd, imm[2:0] (I type, FU_FETCH_TRADE)
        op_custom2   = 7'b1011011  // pkt_w / pkt_s — TX primitive (I type, FU_PKT_TX)
    } rv32i_opcode;

    // Branch funct3 codes
    typedef enum logic [2:0] {
        beq  = 3'b000,
        bne  = 3'b001,
        blt  = 3'b100,
        bge  = 3'b101,
        bltu = 3'b110,
        bgeu = 3'b111
    } branch_funct3_t;

    typedef enum logic [0:0] {
        taken = 1'b1,
        not_taken = 1'b0
    } br_pred_t;

    // Comparator operation codes
    typedef enum logic [2:0] {
        cmp_eq  = 3'b000,
        cmp_ne  = 3'b001,
    // Just for Branch functional unit to know what kind of instruction it is
        jal     = 3'b010, 
        jalr    = 3'b011, 
    //-----------------------------------------------------------------------
        cmp_lt  = 3'b100,
        cmp_ge  = 3'b101,
        cmp_ltu = 3'b110,
        cmp_geu = 3'b111
    } cmp_ops;

    // Load funct3 codes
    typedef enum logic [2:0] {
        lb  = 3'b000,
        lh  = 3'b001,
        lw  = 3'b010,
        lbu = 3'b100,
        lhu = 3'b101
    } load_funct3_t;

    // Store funct3 codes
    typedef enum logic [2:0] {
        sb = 3'b000,
        sh = 3'b001,
        sw = 3'b010
    } store_funct3_t;

    // Memory type union for debugging in Verdi
    typedef union packed {
        load_funct3_t   load_type;
        store_funct3_t  store_type;
    } mem_type_t;

    // Memory operation type
    typedef enum logic {
        mem_load  = 1'b0,
        mem_store = 1'b1
    } mem_op_t;

    // Arithmetic funct3 codes
    typedef enum logic [2:0] {
        add  = 3'b000, //check logic 30 for sub if op_reg opcode
        sll  = 3'b001,
        slt  = 3'b010,
        sltu = 3'b011,
        axor = 3'b100,
        sr   = 3'b101, //check logic 30 for logical/arithmetic
        aor  = 3'b110,
        aand = 3'b111
    } arith_funct3_t;

    // ALU operation codes
    typedef enum logic [2:0] {
        alu_add = 3'b000,
        alu_sll = 3'b001,
        alu_sra = 3'b010,
        alu_sub = 3'b011,
        alu_xor = 3'b100,
        alu_srl = 3'b101,
        alu_or  = 3'b110,
        alu_and = 3'b111
    } alu_ops;

    // ALU 1st operand select codes
    typedef enum logic {
        rs1_out = 1'b0,
        pc_out  = 1'b1
    } alu_op1_sel_t;

    // ALU 2nd operand select codes
    typedef enum logic {
        rs2_out   = 1'b0,
        imm_out   = 1'b1
    } alu_op2_sel_t;

    typedef enum logic [1:0] {
        mul     = 2'b00,
        mulh    = 2'b01,
        mulhsu  = 2'b10,
        mulhu   = 2'b11
    } mul_ops;

    typedef enum logic [1:0] {
        div     = 2'b00,
        divu    = 2'b01,
        rem     = 2'b10,
        remu    = 2'b11
    } div_ops;

    // Divider FSM states
    typedef enum logic [1:0] {
        IDLE     = 2'b00,  // Waiting for new division request
        DIVIDING = 2'b01,  // Division in progress
        COMPLETE = 2'b10   // Division done, broadcasting result
    } div_state_t;

    // Functional Unit flags, for identifying which FU's queue to send to
    typedef enum logic [2:0] {
        FU_ALU         = 3'b000,
        FU_BR          = 3'b001,
        FU_MEM         = 3'b010,
        FU_FETCH_TRADE = 3'b011, // custom-1: BRAM-backed parsed-field read
        FU_MUL         = 3'b100,
        FU_DIV         = 3'b101,
        FU_PKT_TX      = 3'b110  // custom-2: BRAM-backed TX primitive (pkt_w/pkt_s)
    } fu_flags;

    // Register Alias Table and Retirement Register Alias Table entry
    typedef struct packed {
        logic [5:0] phys_reg;
        logic       ready;
        logic       valid;
    } rat_entry_t;

    // Fetch packet structure. Packets sent from Fetch to Decode stage
    typedef union packed {

        struct packed {
            logic        valid;
            br_pred_t    br_pred;
            logic [1:0]  pht_counter;  
            logic [7:0]  pht_index;    
            logic [31:0] inst;
            logic [31:0] pc;
            logic [31:0] pc_next;
        } fields;

        logic [$bits(fields) - 1:0] raw;
    } fetch_packet_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] pc_next;
        br_pred_t    branch_predict;   
        logic [1:0]  pht_counter;      
        logic [7:0]  pht_index;        
    } fetch_stage_t;

    // Decode packet structure. Packets sent from Decode to Rename stage
    typedef struct packed {
        logic           valid;
        logic [31:0]    inst;
        logic [31:0]    pc;
        logic [4:0]     rs1_addr;
        logic [4:0]     rs2_addr;
        logic [31:0]    imm;
        logic [4:0]     rd_addr;
        fu_flags        fu_flag;
        alu_ops         alu_op;
        alu_op1_sel_t   alu_op1_sel;
        alu_op2_sel_t   alu_op2_sel;
        cmp_ops         cmp_op;
        mul_ops         mul_op;
        div_ops         div_op;
        br_pred_t       br_pred;
        logic [1:0]     pht_counter;   
        logic [7:0]     pht_index;     
        mem_type_t      mem_type;
        mem_op_t        mem_op_type;
    } decode_packet_t;

    // Rename Packet structure. Packets sent from Rename to Dispatch stage
    typedef struct packed {
        logic           valid;
        logic [31:0]    inst;
        logic [31:0]    pc;
        logic [5:0]     rs1_paddr;
        logic [5:0]     rs2_paddr;
        logic           rs1_ready;
        logic           rs2_ready;
        logic [31:0]    imm;
        logic [5:0]     rd_paddr;
        logic [4:0]     rd_addr;
        fu_flags        fu_flag;
        alu_ops         alu_op;
        alu_op1_sel_t   alu_op1_sel;
        alu_op2_sel_t   alu_op2_sel;
        cmp_ops         cmp_op;
        mul_ops         mul_op;
        div_ops         div_op;
        logic [1:0]     pht_counter;   
        logic [7:0]     pht_index;     
        mem_type_t      mem_type;
        mem_op_t        mem_op_type;

        logic [$clog2(ROB_SIZE)-1:0] rob_index;
    } rename_packet_t;

    typedef enum logic [0:0] 
    {
        WAIT,
        READY
    } rob_state;

    typedef struct packed {
        logic          valid;
        rob_state      state; 
        logic [31:0]   pc;   // DEBUG_ONLY
        logic [31:0]   inst; // DEBUG_ONLY
        logic [63:0]   order; // DEBUG_ONLY
        logic [4:0]    rd_addr;
        logic [5:0]    rd_paddr;
        br_pred_t      br_pred;
        br_pred_t      br_result;
        logic [1:0]    pht_counter;   
        logic [7:0]    pht_index;      
        logic [31:0]   branch_target; 

        rvfi_packet_t   rvfi_pkt;       
    } rob_entry_t;

    // Simplified ROB commit packet for RRAT - only fields needed for retirement
    typedef struct packed {
        logic          valid;
        logic [4:0]    rd_addr;
        logic [5:0]    rd_paddr;
    } rob_commit_pkt;

    typedef struct packed {
        logic          valid;
        logic [5:0]    rs1_paddr;
        logic [5:0]    rs2_paddr;
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
        logic          rs1_ready;
        logic          rs2_ready;
        cmp_ops        cmp_op;
        logic [31:0]   pc;
        logic [31:0]   imm;
        logic [1:0]    pht_counter;   
        logic [7:0]    pht_index;     
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
    } rs_br_entry_t;

    typedef struct packed {
        logic          valid;
        logic [31:0]   op_a;
        logic [31:0]   op_b;
        cmp_ops        cmp_op;
        logic [31:0]   pc;
        logic [31:0]   imm;
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
        logic [1:0]    pht_counter;   
        logic [7:0]    pht_index;     
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
    } fu_br_pkt;

    typedef struct packed {
        logic          valid;
        logic [31:0]   result;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
        logic [31:0]   rs1_val;
        logic [31:0]   rs2_val;
        logic [31:0]   branch_target;
        br_pred_t      br_result;
        logic [1:0]    pht_counter;   
        logic [7:0]    pht_index;
        logic          is_conditional; // 1 for conditional branches, 0 for JAL/JALR
    } cdb_br_pkt;

    // Simplified CDB wakeup packet - only contains fields needed for wakeup logic
    typedef struct packed {
        logic          valid;
        logic [5:0]    rd_paddr;
    } cdb_wakeup_pkt;

    // BP update queue entry
    typedef struct packed {
        logic          outcome;     // Branch outcome (taken/not taken)
        logic [7:0]    index;       // PHT index
        logic [1:0]    counter;     
    } bp_update_entry_t;

    // Simplified CDB packet for RAT updates - contains fields needed for RAT ready updates
    typedef struct packed {
        logic          valid;
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
    } cdb_rat_pkt;

    // Simplified CDB packets for ROB updates
    typedef struct packed {
        logic          valid;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [31:0]   result;
        logic [31:0]   rs1_val;
        logic [31:0]   rs2_val;
        logic [31:0]   branch_target;
        br_pred_t      br_result;
    } cdb_alu_br_rob_pkt;

    typedef struct packed {
        logic          valid;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [31:0]   result;
        logic [31:0]   rs1_val;
        logic [31:0]   rs2_val;
    } cdb_mul_div_rob_pkt;

    typedef struct packed {
        logic           valid;
        logic [5:0]     rs1_paddr;
        logic [5:0]     rs2_paddr;
        logic [5:0]     rd_paddr;
        logic [4:0]     rd_addr;
        logic           rs1_ready;
        logic           rs2_ready;
        alu_op1_sel_t   alu_op1_sel;
        alu_op2_sel_t   alu_op2_sel;
        logic [31:0]    pc;
        logic [31:0]    imm;
        alu_ops         alu_op;
        cmp_ops         cmp_op;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
    } rs_alu_entry_t;

    typedef struct packed {
        logic          valid;
        logic [31:0]   op_a;
        logic [31:0]   op_b;
        alu_ops        alu_op;
        cmp_ops        cmp_op;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
    } fu_alu_pkt;

    typedef struct packed {
        logic          valid;
        logic [31:0]   result;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
        logic [31:0]   rs1_val;
        logic [31:0]   rs2_val;
    } cdb_alu_pkt;

    // fetch_trade RS entry. Custom-1 has no source operands (rs1=x0, no rs2),
    // so the wakeup machinery is vestigial — rs*_ready are forced high at dispatch.
    typedef struct packed {
        logic          valid;
        logic [2:0]    field_idx;       // BRAM read address (from imm[2:0])
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
    } rs_fetch_trade_entry_t;

    // fetch_trade FU input. field_idx selects which parser-output BRAM entry
    // to return; the FU emits cdb_mul_div_pkt to share the mul/div CDB lane.
    typedef struct packed {
        logic          valid;
        logic [2:0]    field_idx;
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
    } fu_fetch_trade_pkt;

    // pkt_tx RS entry. Custom-2 takes one source operand (rs1):
    //   pkt_w rd, rs1, off  — write rs1 (4 bytes) to TX BRAM[word_offset]
    //   pkt_s rd, rs1       — start emitting first rs1 bytes onto AXI-Stream
    // is_send distinguishes; word_offset is meaningful only when is_send=0.
    typedef struct packed {
        logic          valid;
        logic [5:0]    rs1_paddr;
        logic          rs1_ready;
        logic [3:0]    word_offset;
        logic          is_send;
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
    } rs_pkt_tx_entry_t;

    // pkt_tx FU input. data carries rs1 (the value to write for pkt_w, or
    // the length in octets for pkt_s). The FU shares the mul/div CDB lane.
    typedef struct packed {
        logic          valid;
        logic [31:0]   data;
        logic [3:0]    word_offset;
        logic          is_send;
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
    } fu_pkt_tx_pkt;

    typedef struct packed {
        logic           valid;
        logic [5:0]     rs1_paddr;
        logic [5:0]     rs2_paddr;
        logic [5:0]     rd_paddr;
        logic [4:0]     rd_addr;
        logic           rs1_ready;
        logic           rs2_ready;
        mul_ops         mul_op;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
    } rs_mul_entry_t;

    typedef struct packed {
        logic          valid;
        logic [31:0]   op_a;
        logic [31:0]   op_b;
        mul_ops        mul_op;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
    } fu_mul_pkt;

    typedef struct packed {
        logic           valid;
        logic [5:0]     rs1_paddr;
        logic [5:0]     rs2_paddr;
        logic [5:0]     rd_paddr;
        logic [4:0]     rd_addr;
        logic           rs1_ready;
        logic           rs2_ready;
        div_ops         div_op;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
    } rs_div_entry_t;

    typedef struct packed {
        logic          valid;
        logic [31:0]   op_a;
        logic [31:0]   op_b;
        div_ops        div_op;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
    } fu_div_pkt;

    typedef struct packed {
        logic           valid;
        logic [31:0]    result;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [5:0]     rd_paddr;
        logic [4:0]     rd_addr;
        logic [31:0]    rs1_val;
        logic [31:0]    rs2_val;
    } cdb_mul_div_pkt;

    // Combined CDB packet for ALU and BR (similar to mul_div combining)
    typedef struct packed {
        logic          valid;
        logic [31:0]   result;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [5:0]    rd_paddr;
        logic [4:0]    rd_addr;
        logic [31:0]   rs1_val;
        logic [31:0]   rs2_val;
        logic [31:0]   branch_target;
        br_pred_t      br_result;
    } cdb_alu_br_pkt;

    typedef struct packed {
        logic           valid;
        logic [5:0]     rs1_paddr;
        logic [5:0]     rs2_paddr;
        logic [5:0]     rd_paddr;
        logic [4:0]     rd_addr;
        logic           rs1_ready;
        logic           rs2_ready;
        mem_op_t        mem_op;
        mem_type_t      mem_type;
        logic [31:0]    pc;
        logic [31:0]    imm;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [$clog2(LSQ_SIZE)-1:0] lsq_index;  // Physical LSQ index for direct update
    } rs_mem_entry_t;

    typedef struct packed {
        logic           valid;
        logic           addr_valid;
        logic [LSQ_SIZE-1:0]    dependency_mask;  // One-hot mask for store dependencies
        logic [31:0]    addr;
        logic [31:0]    data;
        mem_op_t        mem_op;
        mem_type_t      mem_type;
        logic [5:0]     rd_paddr;
        logic [4:0]     rd_addr;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [31:0]    rs1_val;
        logic [31:0]    rs2_val;
    } lsq_entry_t;

    typedef struct packed {
        logic           valid;
        logic [31:0]    addr;
        logic [31:0]    data;
        mem_op_t        mem_op;
        mem_type_t      mem_type;
        logic [5:0]     rd_paddr;
        logic [4:0]     rd_addr;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [31:0]    rs1_val;
        logic [31:0]    rs2_val;
    } fu_mem_pkt;

    typedef struct packed {
        logic           valid;
        logic [31:0]    result;
        logic [$clog2(ROB_SIZE)-1:0] rob_index;
        logic [5:0]     rd_paddr;
        logic [4:0]     rd_addr;
        logic [31:0]    rs1_val;
        logic [31:0]    rs2_val;
        logic [31:0]    mem_addr;
        logic [3:0]     mem_rmask;
        logic [3:0]     mem_wmask;
        logic [31:0]    mem_rdata;
        logic [31:0]    mem_wdata;
    } cdb_mem_pkt;


    // Instruction structure, for all instruction formats
    typedef union packed {
        logic [31:0] word;

        struct packed {
            logic [11:0] imm;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  rd;
            rv32i_opcode opcode;
        } i_type;

        struct packed {
            logic [6:0]  funct7;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  rd;
            rv32i_opcode opcode;
        } r_type;

        struct packed {
            logic [11:5] imm_s_top;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  imm_s_bot;
            rv32i_opcode opcode;
        } s_type;

        struct packed {
            logic [31:12] imm;
            logic [4:0]   rd;
            rv32i_opcode  opcode;
        } u_type; 

        struct packed {
            logic [31:12] imm;
            logic [4:0]   rd;
            rv32i_opcode  opcode;
        } j_type;

        struct packed {
            logic        imm_12;        
            logic [5:0]  imm_10_5;      
            logic [4:0]  rs2;           
            logic [4:0]  rs1;           
            logic [2:0]  funct3;        
            logic [3:0]  imm_4_1;       
            logic        imm_11;        
            rv32i_opcode opcode;       
        } b_type;

    } instr_t;


endpackage