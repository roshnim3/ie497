module mem
import ooo_types::*;
(
    input  logic            clk,
    input  logic            rst,
    input  logic            flush,
    
    // Input from LSQ
    input  fu_mem_pkt       mem_pkt_in,
    
    // Output to LSQ indicating ready to accept new packet
    output logic            fu_mem_ready,
    input  logic            cache_ready,
    
    // Cache interface
    output logic   [31:0]   cache_addr,
    output logic   [3:0]    cache_rmask,
    output logic   [3:0]    cache_wmask,
    input  logic   [31:0]   cache_rdata,
    output logic   [31:0]   cache_wdata,
    input  logic            cache_resp,
    
    output cdb_mem_pkt      cdb_mem
);

    // Latched memory packet
    fu_mem_pkt mem_pkt_s0;
    
    // Pipeline control signals
    logic s0_advance;       // s0 completes (cache_resp)
    logic s0_load_new;      // s0 accepts new packet
    
    // Pipeline move logic:
    // s0 advances when cache responds
    assign s0_advance = mem_pkt_s0.valid && cache_resp;
    
    // Accept new packet when:
    // - New packet is valid
    // - s0 is empty OR s0 is advancing this cycle
    assign s0_load_new = mem_pkt_in.valid && (!mem_pkt_s0.valid || s0_advance);
    
    // Ready when cache can take request OR pipeline is moving (no stall)
    assign fu_mem_ready = !flush && (cache_ready || s0_advance || !mem_pkt_s0.valid);

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            mem_pkt_s0 <= '0;
        end else begin
            if (s0_advance && !s0_load_new) begin
                // Response received, no new packet - invalidate s0
                mem_pkt_s0 <= '0;
            end else if (s0_load_new) begin
                // Load new packet
                mem_pkt_s0 <= mem_pkt_in;
            end
        end
    end

    always_comb begin
        cache_addr  = {mem_pkt_in.addr[31:2], 2'b00};
        cache_wdata = 32'b0;
        cache_rmask = 4'b0000;
        cache_wmask = 4'b0000;

        if (mem_pkt_in.valid) begin
            if (mem_pkt_in.mem_op == mem_store) begin
                unique case (mem_pkt_in.mem_type.store_type)
                    sb: begin
                        cache_wmask = 4'b0001 << mem_pkt_in.addr[1:0];
                        unique case (mem_pkt_in.addr[1:0])
                            2'b00: cache_wdata = {24'b0, mem_pkt_in.data[7:0]};
                            2'b01: cache_wdata = {16'b0, mem_pkt_in.data[7:0], 8'b0};
                            2'b10: cache_wdata = {8'b0, mem_pkt_in.data[7:0], 16'b0};
                            2'b11: cache_wdata = {mem_pkt_in.data[7:0], 24'b0};
                        endcase
                    end
                    sh: begin
                        cache_wmask = 4'b0011 << mem_pkt_in.addr[1:0];
                        unique case (mem_pkt_in.addr[1])
                            1'b0: cache_wdata = {16'b0, mem_pkt_in.data[15:0]};
                            1'b1: cache_wdata = {mem_pkt_in.data[15:0], 16'b0};
                        endcase
                    end
                    sw: begin
                        cache_wmask = 4'b1111;
                        cache_wdata = mem_pkt_in.data;
                    end
                    default: begin
                        cache_wmask = 4'b0000;
                        cache_wdata = 32'b0;
                    end
                endcase
            end else begin
                unique case (mem_pkt_in.mem_type.load_type)
                    lb, lbu: cache_rmask = 4'b0001 << mem_pkt_in.addr[1:0];
                    lh, lhu: cache_rmask = 4'b0011 << mem_pkt_in.addr[1:0];
                    lw:      cache_rmask = 4'b1111;
                    default: cache_rmask = 4'b0000;
                endcase
            end
        end
    end

    // CDB output - populate when cache responds
    always_comb begin
        cdb_mem = '0;
        
        if (mem_pkt_s0.valid && cache_resp) begin
            cdb_mem.valid = 1'b1;
            cdb_mem.rob_index = mem_pkt_s0.rob_index;
            cdb_mem.rd_paddr = mem_pkt_s0.rd_paddr;
            cdb_mem.rd_addr = mem_pkt_s0.rd_addr;
            cdb_mem.rs1_val = mem_pkt_s0.rs1_val;
            cdb_mem.rs2_val = mem_pkt_s0.rs2_val;
            cdb_mem.mem_addr = {mem_pkt_s0.addr[31:2], 2'b00};
            
            if (mem_pkt_s0.mem_op == mem_load) begin
                // Load result
                case (mem_pkt_s0.mem_type.load_type)
                    lb: begin
                        case (mem_pkt_s0.addr[1:0])
                            2'b00: cdb_mem.result = {{24{cache_rdata[7]}}, cache_rdata[7:0]};
                            2'b01: cdb_mem.result = {{24{cache_rdata[15]}}, cache_rdata[15:8]};
                            2'b10: cdb_mem.result = {{24{cache_rdata[23]}}, cache_rdata[23:16]};
                            2'b11: cdb_mem.result = {{24{cache_rdata[31]}}, cache_rdata[31:24]};
                        endcase
                    end
                    lbu: begin
                        case (mem_pkt_s0.addr[1:0])
                            2'b00: cdb_mem.result = {24'b0, cache_rdata[7:0]};
                            2'b01: cdb_mem.result = {24'b0, cache_rdata[15:8]};
                            2'b10: cdb_mem.result = {24'b0, cache_rdata[23:16]};
                            2'b11: cdb_mem.result = {24'b0, cache_rdata[31:24]};
                        endcase
                    end
                    lh: begin
                        case (mem_pkt_s0.addr[1])
                            1'b0: cdb_mem.result = {{16{cache_rdata[15]}}, cache_rdata[15:0]};
                            1'b1: cdb_mem.result = {{16{cache_rdata[31]}}, cache_rdata[31:16]};
                        endcase
                    end
                    lhu: begin
                        case (mem_pkt_s0.addr[1])
                            1'b0: cdb_mem.result = {16'b0, cache_rdata[15:0]};
                            1'b1: cdb_mem.result = {16'b0, cache_rdata[31:16]};
                        endcase
                    end
                    lw: cdb_mem.result = cache_rdata;
                    default: cdb_mem.result = 32'b0;
                endcase
                
                // Load mask
                case (mem_pkt_s0.mem_type.load_type)
                    lb, lbu: cdb_mem.mem_rmask = 4'b0001 << mem_pkt_s0.addr[1:0];
                    lh, lhu: cdb_mem.mem_rmask = 4'b0011 << mem_pkt_s0.addr[1:0];
                    lw:      cdb_mem.mem_rmask = 4'b1111;
                    default: cdb_mem.mem_rmask = 4'b0000;
                endcase
               
                // Load data
                case (mem_pkt_s0.mem_type.load_type)
                    lb, lbu: begin
                        case (mem_pkt_s0.addr[1:0])
                            2'b00: cdb_mem.mem_rdata = {24'b0, cache_rdata[7:0]};
                            2'b01: cdb_mem.mem_rdata = {16'b0, cache_rdata[15:8], 8'b0};
                            2'b10: cdb_mem.mem_rdata = {8'b0, cache_rdata[23:16], 16'b0};
                            2'b11: cdb_mem.mem_rdata = {cache_rdata[31:24], 24'b0};
                        endcase
                    end
                    lh, lhu: begin
                        case (mem_pkt_s0.addr[1])
                            1'b0: cdb_mem.mem_rdata = {16'b0, cache_rdata[15:0]};
                            1'b1: cdb_mem.mem_rdata = {cache_rdata[31:16], 16'b0};
                        endcase
                    end
                    lw: cdb_mem.mem_rdata = cache_rdata;
                    default: cdb_mem.mem_rdata = 32'b0;
                endcase
                
                cdb_mem.mem_wmask = 4'b0000;
                cdb_mem.mem_wdata = 32'b0;
            end else begin
                // Store
                cdb_mem.result = mem_pkt_s0.addr;
                cdb_mem.mem_rmask = 4'b0000;
                cdb_mem.mem_rdata = 32'b0;
               
                // Store mask
                case (mem_pkt_s0.mem_type.store_type)
                    sb: cdb_mem.mem_wmask = 4'b0001 << mem_pkt_s0.addr[1:0];
                    sh: cdb_mem.mem_wmask = 4'b0011 << mem_pkt_s0.addr[1:0];
                    sw: cdb_mem.mem_wmask = 4'b1111;
                    default: cdb_mem.mem_wmask = 4'b0000;
                endcase
                
                // Store data
                case (mem_pkt_s0.mem_type.store_type)
                    sb: begin
                        case (mem_pkt_s0.addr[1:0])
                            2'b00: cdb_mem.mem_wdata = {24'b0, mem_pkt_s0.data[7:0]};
                            2'b01: cdb_mem.mem_wdata = {16'b0, mem_pkt_s0.data[7:0], 8'b0};
                            2'b10: cdb_mem.mem_wdata = {8'b0, mem_pkt_s0.data[7:0], 16'b0};
                            2'b11: cdb_mem.mem_wdata = {mem_pkt_s0.data[7:0], 24'b0};
                        endcase
                    end
                    sh: begin
                        case (mem_pkt_s0.addr[1])
                            1'b0: cdb_mem.mem_wdata = {16'b0, mem_pkt_s0.data[15:0]};
                            1'b1: cdb_mem.mem_wdata = {mem_pkt_s0.data[15:0], 16'b0};
                        endcase
                    end
                    sw: cdb_mem.mem_wdata = mem_pkt_s0.data;
                    default: cdb_mem.mem_wdata = 32'b0;
                endcase
            end
        end
    end

endmodule