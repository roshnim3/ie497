// ===============================================================
// top_tb_pipelined.sv  (pipelined, cache_ready-driven testbench)
// Single-writer policy for ufp_* and golden arrays to avoid ICPD.
// ===============================================================
`timescale 1ns/1ps
`define TB_PROBES 1

module ppcache_tb;

    // -------------------------------------------------------------------------
    // Waveform generation
    // -------------------------------------------------------------------------
    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");
    end

    // -------------------------------------------------------------------------
    // DUT port signals
    // -------------------------------------------------------------------------
    logic           clk;
    logic           rst;

    // UFP (CPU-facing) — driven ONLY by cpu_driver (single writer)
    logic   [31:0]  ufp_addr;
    logic   [3:0]   ufp_rmask;
    logic   [3:0]   ufp_wmask;
    logic   [31:0]  ufp_rdata;
    logic   [31:0]  ufp_wdata;
    logic           ufp_resp;

    // DFP (memory-facing)
    logic   [31:0]  dfp_addr;
    logic           dfp_read;
    logic           dfp_write;
    logic   [255:0] dfp_rdata;
    logic   [255:0] dfp_wdata;
    logic           dfp_resp;

    // Instantiate DUT
    ppcache dut (
        .clk(clk), .rst(rst),
        .ufp_addr(ufp_addr), .ufp_rmask(ufp_rmask),
        .ufp_wmask(ufp_wmask), .ufp_rdata(ufp_rdata),
        .ufp_wdata(ufp_wdata), .ufp_resp(ufp_resp),
        .dfp_addr(dfp_addr), .dfp_read(dfp_read),
        .dfp_write(dfp_write), .dfp_rdata(dfp_rdata),
        .dfp_wdata(dfp_wdata), .dfp_resp(dfp_resp)
    );

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic [31:0] address;
        bit          transaction_type; // 0=read 1=write
        logic [3:0]  rmask;
        logic [3:0]  wmask;
        logic [31:0] wdata;
        logic [255:0] dfp_rdata;
        bit          expected_hit;
    } input_transaction_t;

    typedef struct packed {
        bit           caused_writeback;
        bit           caused_allocate;
        logic [31:0]  ufp_returned_data;
        logic [255:0] dfp_writeback_data;
        logic [31:0]  dfp_writeback_addr;
        logic [31:0]  dfp_allocate_addr;
    } output_transaction_t;

    typedef struct packed {
        input_transaction_t   inp;
        output_transaction_t  golden_out;
    } active_t;

    typedef struct packed {
        logic [31:0]       expected_data;
        input_transaction_t inp;
    } expected_t;

    // Queues
    active_t   active_queue[$];
    expected_t expected_q[$];
    // -------------------------------------------------------------------------
    // Simple memory model: respond to dfp_read / dfp_write after fixed latency
    // -------------------------------------------------------------------------
    always @(dfp_read or dfp_write or posedge rst) begin
        if (rst) begin
            dfp_resp  <= 1'b0;
            dfp_rdata <= '0;
        end else begin
            if (dfp_read) begin
                fork
                    begin
                        // Respond after 10 cycles
                        repeat (10) @(posedge clk);
                        dfp_rdata <= {$random,$random,$random,$random,
                                    $random,$random,$random,$random};
                        dfp_resp  <= 1'b1;
                        @(posedge clk);
                        dfp_resp  <= 1'b0;
                        dfp_rdata <= '0;
                    end
                join_none
            end
            if (dfp_write) begin
                fork
                    begin
                        // Acknowledge write after 10 cycles
                        repeat (10) @(posedge clk);
                        dfp_resp  <= 1'b1;
                        @(posedge clk);
                        dfp_resp  <= 1'b0;
                    end
                join_none
            end
        end
    end


    // -------------------------------------------------------------------------
    // Golden model state (owned by golden_admin process)
    // -------------------------------------------------------------------------
    logic [31:0] data_golden_arrays[4][16][8];
    logic [22:0] tag_golden_arrays[4][16];
    logic        valid_golden_arrays[4][16];
    logic        dirty_golden_arrays[4][16];
    logic [2:0]  plru_golden_array[16];

    // Bookkeeping
    bit verbose_mode = 1;
    int global_cycle;
    always_ff @(posedge clk) if (!rst) global_cycle <= global_cycle + 1; else global_cycle <= 0;

    int transaction_count = 0;
    int error_count = 0;
    int hit_count = 0;
    int miss_count = 0;
    int writeback_count = 0;

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    function automatic void init_golden_arrays();
        for (int w = 0; w < 4; w++)
            for (int s = 0; s < 16; s++) begin
                valid_golden_arrays[w][s] = 0;
                dirty_golden_arrays[w][s] = 0;
                tag_golden_arrays[w][s]   = 0;
                for (int word = 0; word < 8; word++)
                    data_golden_arrays[w][s][word] = 0;
            end
        for (int s = 0; s < 16; s++)
            plru_golden_array[s] = 3'b000;
        if (verbose_mode) $display("[INIT] Golden arrays cleared.");
    endfunction

    function automatic logic [1:0] decode_plru(logic [2:0] bits);
        logic [1:0] victim;
        logic L0=bits[0], L1=bits[1], L2=bits[2];
        victim = (L0==0) ? ((L2==0)?2'd3:2'd2)
                         : ((L1==0)?2'd1:2'd0);
        return victim;
    endfunction

    function automatic logic [2:0] update_plru(logic [2:0] cur, logic [1:0] way);
        logic [2:0] newp = cur;
        case (way)
            2'd0: begin newp[1]=0; newp[0]=0; end
            2'd1: begin newp[1]=1; newp[0]=0; end
            2'd2: begin newp[2]=0; newp[0]=1; end
            2'd3: begin newp[2]=1; newp[0]=1; end
        endcase
        return newp;
    endfunction

    // -------------------------------------------------------------------------
    // Functional golden model (no timing)
    // -------------------------------------------------------------------------
    function automatic output_transaction_t golden_cache_do(input_transaction_t inp);
        output_transaction_t out;
        logic [22:0] tag;
        logic [3:0]  index;
        logic [4:0]  offset;
        logic [1:0]  hit_way, victim_way;
        bit          cache_hit;

        out    = '0;
        tag    = inp.address[31:9];
        index  = inp.address[8:5];
        offset = inp.address[4:0];

        cache_hit = 0;
        for (int w = 0; w < 4; w++)
            if (valid_golden_arrays[w][index] &&
                tag_golden_arrays[w][index] == tag) begin
                cache_hit = 1;
                hit_way   = w[1:0];
                break;
            end

        if (cache_hit) begin
            hit_count++;
            if (inp.transaction_type == 0) begin
                out.ufp_returned_data = data_golden_arrays[hit_way][index][offset[4:2]];
            end else begin
                logic [31:0] cur = data_golden_arrays[hit_way][index][offset[4:2]];
                for (int b=0;b<4;b++)
                    if (inp.wmask[b]) cur[b*8 +: 8] = inp.wdata[b*8 +: 8];
                data_golden_arrays[hit_way][index][offset[4:2]] = cur;
                dirty_golden_arrays[hit_way][index] = 1;
            end
            plru_golden_array[index] = update_plru(plru_golden_array[index], hit_way);
        end else begin
            miss_count++;
            victim_way = decode_plru(plru_golden_array[index]);

            if (valid_golden_arrays[victim_way][index] &&
                dirty_golden_arrays[victim_way][index]) begin
                out.caused_writeback   = 1;
                out.dfp_writeback_addr = {tag_golden_arrays[victim_way][index], index, 5'b0};
                for (int i=0;i<8;i++)
                    out.dfp_writeback_data[i*32 +: 32] = data_golden_arrays[victim_way][index][i];
                writeback_count++;
            end

            out.caused_allocate   = 1;
            out.dfp_allocate_addr = {tag,index,5'b0};

            valid_golden_arrays[victim_way][index] = 1;
            tag_golden_arrays[victim_way][index]   = tag;
            dirty_golden_arrays[victim_way][index] = inp.transaction_type;

            for (int i=0;i<8;i++)
                data_golden_arrays[victim_way][index][i] = inp.dfp_rdata[i*32 +: 32];

            if (inp.transaction_type == 1) begin
                logic [31:0] cur = data_golden_arrays[victim_way][index][offset[4:2]];
                for (int b=0;b<4;b++)
                    if (inp.wmask[b]) cur[b*8 +: 8] = inp.wdata[b*8 +: 8];
                data_golden_arrays[victim_way][index][offset[4:2]] = cur;
            end

            if (inp.transaction_type == 0)
                out.ufp_returned_data = inp.dfp_rdata[offset[4:2]*32 +: 32];

            plru_golden_array[index] = update_plru(plru_golden_array[index], victim_way);
        end

        return out;
    endfunction

    // -------------------------------------------------------------------------
    // CPU driver: sole writer of ufp_*; also runs golden init at reset
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {CPU_IDLE, CPU_ISSUE} cpu_state_e;
    cpu_state_e cpu_state;
    bit         rst_q;

    // latched one-cycle request while issuing
    input_transaction_t cur_inp;
    bit                  cur_inp_valid;

    always_ff @(posedge clk) begin : cpu_driver
        automatic active_t a;
        output_transaction_t g;
        // track reset edge
        rst_q <= rst;

        if (rst) begin
            // Initialize TB-visible CPU signals
            ufp_addr  <= '0;
            ufp_rmask <= '0;
            ufp_wmask <= '0;
            ufp_wdata <= '0;

            // Initialize golden arrays exactly once on reset assertion edge
            if (!rst_q) begin
                init_golden_arrays();
                cpu_state      <= CPU_IDLE;
                cur_inp_valid  <= 0;
            end
        end else begin
            case (cpu_state)
                CPU_IDLE: begin
                    // Default deassert
                    ufp_addr  <= '0;
                    ufp_rmask <= '0;
                    ufp_wmask <= '0;
                    ufp_wdata <= '0;
                    cur_inp_valid <= 0;

                    // If DUT can take a request, pop one and issue
                    if (dut.cache_ready && active_queue.size() > 0) begin
                        a = active_queue.pop_front();

                        // Run golden immediately to update model and get expected data
                        g = golden_cache_do(a.inp);
                        if (a.inp.transaction_type == 0) begin
                            expected_t e;
                            e.expected_data = g.ufp_returned_data;
                            e.inp = a.inp;
                            expected_q.push_back(e);
                        end

                        // Latch current input for a one-cycle pulse
                        cur_inp        <= a.inp;
                        cur_inp_valid  <= 1'b1;

                        // Drive request for one cycle
                        ufp_addr  <= a.inp.address;
                        ufp_rmask <= a.inp.rmask;
                        ufp_wmask <= a.inp.wmask;
                        ufp_wdata <= a.inp.wdata;

                        if (verbose_mode)
                            $display("\n[ISSUE@%0d] %s Addr=%08h",
                                     global_cycle,
                                     a.inp.transaction_type?"WRITE":"READ",
                                     a.inp.address);

                        cpu_state <= CPU_ISSUE;
                    end
                end

                CPU_ISSUE: begin
                    // Deassert after one cycle
                    ufp_addr  <= '0;
                    ufp_rmask <= '0;
                    ufp_wmask <= '0;
                    ufp_wdata <= '0;
                    cur_inp_valid <= 0;
                    cpu_state <= CPU_IDLE;
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Response monitor (passive; does not drive ufp_*)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst && ufp_resp) begin
            if (expected_q.size() == 0) begin
                $error("Unexpected ufp_resp @%0d", global_cycle);
                error_count++;
            end else begin
                automatic expected_t e = expected_q.pop_front();
                if (ufp_rdata !== e.expected_data) begin
                    $error("[MISMATCH] Addr=%08h Exp=%08h Got=%08h",
                           e.inp.address, e.expected_data, ufp_rdata);
                    error_count++;
                end else begin
                    if (verbose_mode)
                        $display("[PASS] Addr=%08h Data=%08h", e.inp.address, ufp_rdata);
                end
                transaction_count++;
            end
        end
    end

`ifdef TB_PROBES
    // Optional internal probe
    always_ff @(posedge clk) begin
        if (!rst) begin
            $display("[DUT@%0d] ready=%0b ufp_resp=%0b dfp_resp=%0b state=%0d",
                     global_cycle, dut.cache_ready, ufp_resp, dfp_resp, dut.state);
        end
    end
`endif

    // -------------------------------------------------------------------------
    // Random traffic generator
    // -------------------------------------------------------------------------
    function automatic input_transaction_t generate_input_transaction();
        input_transaction_t t;
        t.address = $urandom();
        t.address[1:0] = 2'b00;
        t.transaction_type = $urandom_range(0,1);
        t.rmask = t.transaction_type ? 4'b0000 : 4'b1111;
        t.wmask = t.transaction_type ? 4'b1111 : 4'b0000;
        t.wdata = $urandom();
        for (int i=0;i<8;i++)
            t.dfp_rdata[i*32 +: 32] = $urandom();
        t.expected_hit = '0;
        return t;
    endfunction

    // -------------------------------------------------------------------------
    // Compare outputs (kept simple; no timing checks)
    // -------------------------------------------------------------------------
    function automatic void compare_outputs(output_transaction_t g,
                                            output_transaction_t d,
                                            input_transaction_t  inp);
        if (g.caused_writeback != d.caused_writeback)
            $error("WRITEBACK mismatch");
        if (g.caused_allocate != d.caused_allocate)
            $error("ALLOC mismatch");
        if (inp.transaction_type==0 &&
            g.ufp_returned_data !== d.ufp_returned_data)
            $error("DATA mismatch");
    endfunction

    // -------------------------------------------------------------------------
    // Main test
    // -------------------------------------------------------------------------
    initial begin
        // Reset and default memory-side signals
        rst       = 1'b1;
        dfp_resp  = 1'b0;
        dfp_rdata = '0;

        // Simple reset sequence
        repeat(10) @(posedge clk);
        rst = 1'b0;
        repeat(10) @(posedge clk);

        // Preload a batch of transactions
        for (int i=0;i<200;i++) begin
            active_t a;
            a.inp = generate_input_transaction();
            a.golden_out = '0; // not used now; golden is run at issue
            active_queue.push_back(a);
        end

        // Run until all reads have been responded to and queue is empty
        // (If your DUT can generate dfp_read/dfp_write, add a memory model here.)
        
        wait (active_queue.size()==0 && expected_q.size()==0);
        repeat(10) @(posedge clk);

        $display("\n--- Simulation done ---");
        $display("Transactions=%0d Errors=%0d Hits=%0d Misses=%0d WBs=%0d",
                 transaction_count, error_count, hit_count, miss_count, writeback_count);
        $finish;
    end

endmodule
