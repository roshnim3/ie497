module lsq 
import ooo_types::*;
#
(
    parameter LSQ_SIZE = 16
)
(
    input  logic            clk,
    input  logic            rst,
    input  logic            flush,
    
    // Enqueue interface (from RS when entry is allocated)
    input  lsq_entry_t      enq_entry,
    
    // Address/Data update interface (from pipeline stages)
    input  logic            addr_data_valid,
    input  logic [$clog2(LSQ_SIZE)-1:0] addr_data_lsq_index,
    input  logic [31:0]     addr_data_addr,
    input  logic [31:0]     addr_data_data,
    input  logic [31:0]     addr_data_rs1_val,
    input  logic [31:0]     addr_data_rs2_val,

    // ROB head for store ordering
    input  logic [$clog2(ROB_SIZE)-1:0] rob_head_idx,

    // Memory FU interface
    output fu_mem_pkt       fu_mem_out,
    input  logic            fu_mem_ready,
    input  logic            cache_ready,

    // Status
    output logic            full,
    output logic            empty,
    output logic [$clog2(LSQ_SIZE)-1:0] next_lsq_index  // Physical index for next enqueue
);

    // LSQ storage - circular buffer like RS
    lsq_entry_t lsq_mem [LSQ_SIZE];
    logic [$clog2(LSQ_SIZE):0] head, tail;
    
    // Global store mask - one-hot encoding of all valid stores in LSQ
    logic [LSQ_SIZE-1:0] global_store_mask;

    logic [LSQ_SIZE-1:0] issued_store_mask;

    logic [$clog2(LSQ_SIZE):0] ready_idx;

    logic can_issue;
    


    assign empty = (head == tail);
    assign full  = (head[$clog2(LSQ_SIZE)] != tail[$clog2(LSQ_SIZE)]) && 
                   (head[$clog2(LSQ_SIZE)-1:0] == tail[$clog2(LSQ_SIZE)-1:0]);
    assign next_lsq_index = tail[$clog2(LSQ_SIZE)-1:0];  // Physical index where next entry will go

    always_comb begin
        issued_store_mask = '0;
        issued_store_mask[ready_idx[$clog2(LSQ_SIZE)-1:0]] = 1'b1;
    end
    
    always_comb begin
        ready_idx = head;
        can_issue = 1'b0;
        
        // Check head entry first - if it's a store at ROB head, prioritize it
        if (!empty) begin
            logic [$clog2(LSQ_SIZE)-1:0] head_phys_idx;
            head_phys_idx = head[$clog2(LSQ_SIZE)-1:0];
            
            if (lsq_mem[head_phys_idx].valid && 
                lsq_mem[head_phys_idx].addr_valid &&
                lsq_mem[head_phys_idx].mem_op == mem_store &&
                lsq_mem[head_phys_idx].rob_index == rob_head_idx) begin
                // Head is a store at ROB head - must issue it first
                ready_idx = head;
                can_issue = 1'b1;
            end else begin
                // Head is not a ready store, scan for ready loads
                for(integer unsigned i = 0; i < LSQ_SIZE; i++) begin
                    logic [$clog2(LSQ_SIZE):0] curr_idx;
                    curr_idx = head + ($clog2(LSQ_SIZE)+1)'(i);
                    
                    if (curr_idx != tail) begin
                        if (lsq_mem[curr_idx[$clog2(LSQ_SIZE)-1:0]].valid && 
                            lsq_mem[curr_idx[$clog2(LSQ_SIZE)-1:0]].addr_valid &&
                            lsq_mem[curr_idx[$clog2(LSQ_SIZE)-1:0]].mem_op == mem_load &&
                            lsq_mem[curr_idx[$clog2(LSQ_SIZE)-1:0]].dependency_mask == '0) begin
                            ready_idx = curr_idx;
                            can_issue = 1'b1;
                            break;
                        end
                    end
                end
            end
        end
    end
    
    // Combinational output - FU will latch it
    always_comb begin
        fu_mem_out = '0;
        if (!empty && can_issue) begin
            fu_mem_out = '{
                valid: 1'b1,
                addr: lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].addr,
                data: lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].data,
                mem_op: lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].mem_op,
                mem_type: lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].mem_type,
                rd_paddr: lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].rd_paddr,
                rd_addr: lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].rd_addr,
                rob_index: lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].rob_index,
                rs1_val: lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].rs1_val,
                rs2_val: lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].rs2_val
            };
        end 
    end

    // LSQ management - following mem_rs pattern exactly
    always_ff @(posedge clk) begin
        if (rst) begin
            head <= '0;
            tail <= '0;
            global_store_mask <= '0;
            for (integer unsigned i = 0; i < LSQ_SIZE; i++) begin
                lsq_mem[i] <= '0;
            end
        end else if (flush) begin
            head <= '0;
            tail <= '0;
            global_store_mask <= '0;
            for (integer unsigned i = 0; i < LSQ_SIZE; i++) begin
                lsq_mem[i].valid <= '0;
            end
        end else begin
            
            // Enqueue new entry
            if (enq_entry.valid) begin
                lsq_mem[tail[$clog2(LSQ_SIZE)-1:0]] <= enq_entry;
                if (enq_entry.mem_op == mem_store) begin
                    global_store_mask[tail[$clog2(LSQ_SIZE)-1:0]] <= 1'b1;
                    lsq_mem[tail[$clog2(LSQ_SIZE)-1:0]].dependency_mask <= '0;
                end 
                // If enqueueing a load, copy global mask as its dependency mask
                else if (enq_entry.mem_op == mem_load) begin
                    logic [LSQ_SIZE-1:0] load_dep_mask;
                    load_dep_mask = global_store_mask;
                    
                    // Handle race: if a store is issuing this cycle, don't depend on it
                    if (can_issue && fu_mem_ready && cache_ready && lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].mem_op == mem_store) begin
                        load_dep_mask = load_dep_mask ^ issued_store_mask;
                    end
                    
                    lsq_mem[tail[$clog2(LSQ_SIZE)-1:0]].dependency_mask <= load_dep_mask;
                end
                
                tail <= tail + 1'b1;
            end
            
            // Clear dependencies when a store issues (happens for all loads)
            if (can_issue && fu_mem_ready && cache_ready && lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].mem_op == mem_store) begin
                for (integer unsigned i = 0; i < LSQ_SIZE; i++) begin
                    if (lsq_mem[i].valid && lsq_mem[i].mem_op == mem_load) begin
                        lsq_mem[i].dependency_mask[ready_idx[$clog2(LSQ_SIZE)-1:0]] <= 1'b0;
                    end
                end
                
                global_store_mask[ready_idx[$clog2(LSQ_SIZE)-1:0]] <= 1'b0;
            end
            
            // Update address/data when computed - this can refine dependency masks
            // Use else-if to prevent overwriting dependency bits that were just cleared by store issue
            if (addr_data_valid && !(can_issue && fu_mem_ready && cache_ready && lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].mem_op == mem_store)) begin
                lsq_mem[addr_data_lsq_index].addr <= addr_data_addr;
                lsq_mem[addr_data_lsq_index].addr_valid <= 1'b1;
                lsq_mem[addr_data_lsq_index].data <= addr_data_data;
                lsq_mem[addr_data_lsq_index].rs1_val <= addr_data_rs1_val;
                lsq_mem[addr_data_lsq_index].rs2_val <= addr_data_rs2_val;
                
                // Address checking: refine dependency masks based on actual addresses
                if (lsq_mem[addr_data_lsq_index].mem_op == mem_load) begin
                    // For loads: scan backwards from load towards head, checking older stores
                    for (integer unsigned i = 0; i < LSQ_SIZE; i++) begin
                        logic [$clog2(LSQ_SIZE):0] curr_idx;
                        logic [$clog2(LSQ_SIZE)-1:0] curr_phys_idx;
                        
                        curr_idx = head + ($clog2(LSQ_SIZE)+1)'(i);
                        curr_phys_idx = curr_idx[$clog2(LSQ_SIZE)-1:0];
                        
                        if (curr_idx != tail) begin
                            // Stop when we reach the load's position
                            if (curr_phys_idx == addr_data_lsq_index) begin
                                break;
                            end
                            
                            // Depend on older stores if: (1) address matches OR (2) address not yet known
                            if (lsq_mem[curr_phys_idx].valid &&
                                lsq_mem[curr_phys_idx].mem_op == mem_store) begin
                                if (!lsq_mem[curr_phys_idx].addr_valid ||
                                    lsq_mem[curr_phys_idx].addr[31:2] == addr_data_addr[31:2]) begin
                                    lsq_mem[addr_data_lsq_index].dependency_mask[curr_phys_idx] <= 1'b1;
                                end
                            end
                        end
                    end
                end 
                else if (lsq_mem[addr_data_lsq_index].mem_op == mem_store) begin
                    // For stores: scan forwards from store towards tail, checking newer loads
                    logic store_passed;
                    store_passed = 1'b0;
                    
                    for (integer unsigned i = 0; i < LSQ_SIZE; i++) begin
                        logic [$clog2(LSQ_SIZE):0] curr_idx;
                        logic [$clog2(LSQ_SIZE)-1:0] curr_phys_idx;
                        
                        curr_idx = head + ($clog2(LSQ_SIZE)+1)'(i);
                        curr_phys_idx = curr_idx[$clog2(LSQ_SIZE)-1:0];
                        
                        if (curr_idx != tail) begin
                            // Mark when we pass the store's position
                            if (curr_phys_idx == addr_data_lsq_index) begin
                                store_passed = 1'b1;
                            end else if (store_passed) begin
                                // After store's position, check newer loads for address match
                                if (lsq_mem[curr_phys_idx].valid &&
                                    lsq_mem[curr_phys_idx].mem_op == mem_load &&
                                    lsq_mem[curr_phys_idx].addr_valid &&
                                    lsq_mem[curr_phys_idx].addr[31:2] == addr_data_addr[31:2]) begin
                                    lsq_mem[curr_phys_idx].dependency_mask[addr_data_lsq_index] <= 1'b1;
                                end
                            end
                        end
                    end
                end
            end else if (addr_data_valid) begin
                // If a store is issuing same cycle as addr_data update, still update address/data fields
                // but skip the dependency refinement to avoid race condition
                lsq_mem[addr_data_lsq_index].addr <= addr_data_addr;
                lsq_mem[addr_data_lsq_index].addr_valid <= 1'b1;
                lsq_mem[addr_data_lsq_index].data <= addr_data_data;
                lsq_mem[addr_data_lsq_index].rs1_val <= addr_data_rs1_val;
                lsq_mem[addr_data_lsq_index].rs2_val <= addr_data_rs2_val;
            end
            
            // Invalidate entry when issued and accepted by memory FU
            if (can_issue && fu_mem_ready && cache_ready) begin
                lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].valid <= 1'b0;
            end
            
            // Move head forward when head entry is invalid
            if (!empty && !lsq_mem[head[$clog2(LSQ_SIZE)-1:0]].valid) begin
                head <= head + 1'b1;
            end
        end
    end

endmodule : lsq


// module lsq 
// import ooo_types::*;
// #
// (
//     parameter LSQ_SIZE = 16
// )
// (
//     input  logic            clk,
//     input  logic            rst,
//     input  logic            flush,
    
//     // Enqueue interface (from RS when entry is allocated)
//     input  lsq_entry_t      enq_entry,
    
//     // Address/Data update interface (from pipeline stages)
//     input  logic            addr_data_valid,
//     input  logic [$clog2(LSQ_SIZE)-1:0] addr_data_lsq_index,
//     input  logic [31:0]     addr_data_addr,
//     input  logic [31:0]     addr_data_data,
//     input  logic [31:0]     addr_data_rs1_val,
//     input  logic [31:0]     addr_data_rs2_val,

//     // ROB head for store ordering
//     input  logic [$clog2(ROB_SIZE)-1:0] rob_head_idx,

//     // Memory FU interface
//     output fu_mem_pkt       fu_mem_out,
//     input  logic            fu_mem_ready,
//     input  logic            cache_ready,

//     // Status
//     output logic            full,
//     output logic            empty,
//     output logic [$clog2(LSQ_SIZE)-1:0] next_lsq_index  // Physical index for next enqueue
// );

//     // LSQ storage - circular buffer like RS
//     lsq_entry_t lsq_mem [LSQ_SIZE];
//     logic [$clog2(LSQ_SIZE):0] head, tail;
    
//     // Global store mask - one-hot encoding of all valid stores in LSQ
//     logic [LSQ_SIZE-1:0] global_store_mask;

//     logic [LSQ_SIZE-1:0] issued_store_mask;

//     logic [$clog2(LSQ_SIZE):0] ready_idx;

//     logic can_issue;

//     // ----------------------------------------------------------------
//     // Pipeline registers for dependency refinement (new)
//     // ----------------------------------------------------------------
//     logic                           dep_refine_valid;
//     logic [$clog2(LSQ_SIZE)-1:0]    dep_refine_index;
//     logic [31:0]                    dep_refine_addr;
//     logic                           dep_refine_is_load;
//     logic                           dep_refine_is_store;

//     assign empty = (head == tail);
//     assign full  = (head[$clog2(LSQ_SIZE)] != tail[$clog2(LSQ_SIZE)]) && 
//                    (head[$clog2(LSQ_SIZE)-1:0] == tail[$clog2(LSQ_SIZE)-1:0]);
//     assign next_lsq_index = tail[$clog2(LSQ_SIZE)-1:0];  // Physical index where next entry will go

//     always_comb begin
//         issued_store_mask = '0;
//         issued_store_mask[ready_idx[$clog2(LSQ_SIZE)-1:0]] = 1'b1;
//     end
    
//     always_comb begin
//         ready_idx = head;
//         can_issue = 1'b0;
        
//         // Check head entry first - if it's a store at ROB head, prioritize it
//         if (!empty) begin
//             logic [$clog2(LSQ_SIZE)-1:0] head_phys_idx;
//             head_phys_idx = head[$clog2(LSQ_SIZE)-1:0];
            
//             if (lsq_mem[head_phys_idx].valid && 
//                 lsq_mem[head_phys_idx].addr_valid &&
//                 lsq_mem[head_phys_idx].mem_op == mem_store &&
//                 lsq_mem[head_phys_idx].rob_index == rob_head_idx) begin
//                 // Head is a store at ROB head - must issue it first
//                 ready_idx = head;
//                 can_issue = 1'b1;
//             end else begin
//                 // Head is not a ready store, scan for ready loads
//                 for (integer unsigned i = 0; i < LSQ_SIZE; i++) begin
//                     logic [$clog2(LSQ_SIZE):0] curr_idx;
//                     curr_idx = head + ($clog2(LSQ_SIZE)+1)'(i);
                    
//                     if (curr_idx != tail) begin
//                         if (lsq_mem[curr_idx[$clog2(LSQ_SIZE)-1:0]].valid && 
//                             lsq_mem[curr_idx[$clog2(LSQ_SIZE)-1:0]].addr_valid &&
//                             lsq_mem[curr_idx[$clog2(LSQ_SIZE)-1:0]].mem_op == mem_load &&
//                             lsq_mem[curr_idx[$clog2(LSQ_SIZE)-1:0]].dependency_mask == '0) begin
//                             ready_idx = curr_idx;
//                             can_issue = 1'b1;
//                             break;
//                         end
//                     end
//                 end
//             end
//         end
//     end
    
//     // Combinational output - FU will latch it
//     always_comb begin
//         fu_mem_out = '0;
//         if (!empty && can_issue) begin
//             fu_mem_out = '{
//                 valid:    1'b1,
//                 addr:     lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].addr,
//                 data:     lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].data,
//                 mem_op:   lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].mem_op,
//                 mem_type: lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].mem_type,
//                 rd_paddr: lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].rd_paddr,
//                 rd_addr:  lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].rd_addr,
//                 rob_index:lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].rob_index,
//                 rs1_val:  lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].rs1_val,
//                 rs2_val:  lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].rs2_val
//             };
//         end 
//     end

//     //-----------------------------------------------------------------
//     // LSQ management + addr/data update + schedule dependency refine
//     //-----------------------------------------------------------------
//     always_ff @(posedge clk) begin
//         if (rst) begin
//             head <= '0;
//             tail <= '0;
//             global_store_mask <= '0;
//             dep_refine_valid <= 1'b0;
//             for (integer unsigned i = 0; i < LSQ_SIZE; i++) begin
//                 lsq_mem[i] <= '0;
//             end
//         end else if (flush) begin
//             head <= '0;
//             tail <= '0;
//             global_store_mask <= '0;
//             dep_refine_valid <= 1'b0;
//             for (integer unsigned i = 0; i < LSQ_SIZE; i++) begin
//                 lsq_mem[i].valid <= '0;
//             end
//         end else begin
//             // Default: no new refine unless we explicitly schedule it
//             dep_refine_valid <= 1'b0;

//             // Enqueue new entry
//             if (enq_entry.valid) begin
//                 lsq_mem[tail[$clog2(LSQ_SIZE)-1:0]] <= enq_entry;
//                 if (enq_entry.mem_op == mem_store) begin
//                     global_store_mask[tail[$clog2(LSQ_SIZE)-1:0]] <= 1'b1;
//                     lsq_mem[tail[$clog2(LSQ_SIZE)-1:0]].dependency_mask <= '0;
//                 end 
//                 // If enqueueing a load, copy global mask as its dependency mask
//                 else if (enq_entry.mem_op == mem_load) begin
//                     logic [LSQ_SIZE-1:0] load_dep_mask;
//                     load_dep_mask = global_store_mask;
                    
//                     // Handle race: if a store is issuing this cycle, don't depend on it
//                     if (can_issue && fu_mem_ready && cache_ready &&
//                         lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].mem_op == mem_store) begin
//                         load_dep_mask = load_dep_mask ^ issued_store_mask;
//                     end
                    
//                     lsq_mem[tail[$clog2(LSQ_SIZE)-1:0]].dependency_mask <= load_dep_mask;
//                 end
                
//                 tail <= tail + 1'b1;
//             end
            
//             // Clear dependencies when a store issues (happens for all loads)
//             if (can_issue && fu_mem_ready && cache_ready &&
//                 lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].mem_op == mem_store) begin
//                 for (integer unsigned i = 0; i < LSQ_SIZE; i++) begin
//                     if (lsq_mem[i].valid && lsq_mem[i].mem_op == mem_load) begin
//                         lsq_mem[i].dependency_mask[ready_idx[$clog2(LSQ_SIZE)-1:0]] <= 1'b0;
//                     end
//                 end
                
//                 global_store_mask[ready_idx[$clog2(LSQ_SIZE)-1:0]] <= 1'b0;
//             end
            
//             // Update address/data when computed.
//             // Now we only schedule dependency refinement; the big loops are in a separate always_ff.
//             if (addr_data_valid &&
//                 !(can_issue && fu_mem_ready && cache_ready &&
//                   lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].mem_op == mem_store)) begin
//                 lsq_mem[addr_data_lsq_index].addr       <= addr_data_addr;
//                 lsq_mem[addr_data_lsq_index].addr_valid <= 1'b1;
//                 lsq_mem[addr_data_lsq_index].data       <= addr_data_data;
//                 lsq_mem[addr_data_lsq_index].rs1_val    <= addr_data_rs1_val;
//                 lsq_mem[addr_data_lsq_index].rs2_val    <= addr_data_rs2_val;
                
//                 // Schedule dependency refinement for next cycle
//                 dep_refine_valid    <= 1'b1;
//                 dep_refine_index    <= addr_data_lsq_index;
//                 dep_refine_addr     <= addr_data_addr;
//                 dep_refine_is_load  <= (lsq_mem[addr_data_lsq_index].mem_op == mem_load);
//                 dep_refine_is_store <= (lsq_mem[addr_data_lsq_index].mem_op == mem_store);

//             end else if (addr_data_valid) begin
//                 // If a store is issuing same cycle as addr_data update, still update address/data fields
//                 // but skip the dependency refinement to avoid race condition
//                 lsq_mem[addr_data_lsq_index].addr       <= addr_data_addr;
//                 lsq_mem[addr_data_lsq_index].addr_valid <= 1'b1;
//                 lsq_mem[addr_data_lsq_index].data       <= addr_data_data;
//                 lsq_mem[addr_data_lsq_index].rs1_val    <= addr_data_rs1_val;
//                 lsq_mem[addr_data_lsq_index].rs2_val    <= addr_data_rs2_val;
//                 // dep_refine_valid stays 0 here (no refine this cycle or next)
//             end
            
//             // Invalidate entry when issued and accepted by memory FU
//             if (can_issue && fu_mem_ready && cache_ready) begin
//                 lsq_mem[ready_idx[$clog2(LSQ_SIZE)-1:0]].valid <= 1'b0;
//             end
            
//             // Move head forward when head entry is invalid
//             if (!empty && !lsq_mem[head[$clog2(LSQ_SIZE)-1:0]].valid) begin
//                 head <= head + 1'b1;
//             end

//             if (dep_refine_valid) begin
//                 if (dep_refine_is_load) begin
//                     // For loads: scan backwards from load towards head, checking older stores
//                     for (integer unsigned i = 0; i < LSQ_SIZE; i++) begin
//                         logic [$clog2(LSQ_SIZE):0] curr_idx;
//                         logic [$clog2(LSQ_SIZE)-1:0] curr_phys_idx;
                        
//                         curr_idx      = head + ($clog2(LSQ_SIZE)+1)'(i);
//                         curr_phys_idx = curr_idx[$clog2(LSQ_SIZE)-1:0];
                        
//                         if (curr_idx != tail) begin
//                             // Stop when we reach the load's position
//                             if (curr_phys_idx == dep_refine_index) begin
//                                 break;
//                             end
                            
//                             // Depend on older stores if: (1) address matches OR (2) address not yet known
//                             if (lsq_mem[curr_phys_idx].valid &&
//                                 lsq_mem[curr_phys_idx].mem_op == mem_store) begin
//                                 if (!lsq_mem[curr_phys_idx].addr_valid ||
//                                     lsq_mem[curr_phys_idx].addr[31:2] == dep_refine_addr[31:2]) begin
//                                     lsq_mem[dep_refine_index].dependency_mask[curr_phys_idx] <= 1'b1;
//                                 end
//                             end
//                         end
//                     end
//                 end else if (dep_refine_is_store) begin
//                     // For stores: scan forwards from store towards tail, checking newer loads
//                     logic store_passed;
//                     store_passed = 1'b0;
                    
//                     for (integer unsigned i = 0; i < LSQ_SIZE; i++) begin
//                         logic [$clog2(LSQ_SIZE):0] curr_idx;
//                         logic [$clog2(LSQ_SIZE)-1:0] curr_phys_idx;
                        
//                         curr_idx      = head + ($clog2(LSQ_SIZE)+1)'(i);
//                         curr_phys_idx = curr_idx[$clog2(LSQ_SIZE)-1:0];
                        
//                         if (curr_idx != tail) begin
//                             // Mark when we pass the store's position
//                             if (curr_phys_idx == dep_refine_index) begin
//                                 store_passed = 1'b1;
//                             end else if (store_passed) begin
//                                 // After store's position, check newer loads for address match
//                                 if (lsq_mem[curr_phys_idx].valid &&
//                                     lsq_mem[curr_phys_idx].mem_op == mem_load &&
//                                     lsq_mem[curr_phys_idx].addr_valid &&
//                                     lsq_mem[curr_phys_idx].addr[31:2] == dep_refine_addr[31:2]) begin
//                                     lsq_mem[curr_phys_idx].dependency_mask[dep_refine_index] <= 1'b1;
//                                 end
//                             end
//                         end
//                     end
//                 end
//             end
//         end
//     end

// endmodule : lsq
