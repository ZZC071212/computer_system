`include "core_struct.vh"
`include "csr_struct.vh"
`include "mem_ift.vh"

module MMU(
    input clk,
    input rst,
    input CorePack::data_t satp,
    input [1:0] priv,
    input switch_mode,
    input CorePack::data_t pc_if,
    input CorePack::data_t pc_mem,

    output CsrPack::ExceptPack except_mmu,

    Mem_ift.Slave core_imem_ift,
    Mem_ift.Slave core_dmem_ift,

    Mem_ift.Master mem_imem_ift,
    Mem_ift.Master mem_dmem_ift
);

    CsrPack::ExceptPack except_imem;
    CsrPack::ExceptPack except_dmem;

    MMUChannel #(
        .IS_INST(1'b1)
    ) imem_mmu (
        .clk(clk),
        .rst(rst),
        .satp(satp),
        .priv(priv),
        .switch_mode(switch_mode),
        .pc_fault(pc_if),
        .except_mmu(except_imem),
        .core_ift(core_imem_ift),
        .mem_ift(mem_imem_ift)
    );

    MMUChannel #(
        .IS_INST(1'b0)
    ) dmem_mmu (
        .clk(clk),
        .rst(rst),
        .satp(satp),
        .priv(priv),
        .switch_mode(switch_mode),
        .pc_fault(pc_mem),
        .except_mmu(except_dmem),
        .core_ift(core_dmem_ift),
        .mem_ift(mem_dmem_ift)
    );

    assign except_mmu = except_dmem.except ? except_dmem : except_imem;

endmodule

module MMUChannel #(
    parameter logic IS_INST = 1'b0
) (
    input clk,
    input rst,
    input CorePack::data_t satp,
    input [1:0] priv,
    input switch_mode,
    input CorePack::data_t pc_fault,

    output CsrPack::ExceptPack except_mmu,

    Mem_ift.Slave core_ift,
    Mem_ift.Master mem_ift
);
    import CorePack::*;
    import CsrPack::*;

    localparam logic [1:0] PRIV_M = 2'b11;
    localparam logic [1:0] PRIV_U = 2'b00;
    localparam data_t SATP_MODE_SV39 = 64'h8000_0000_0000_0000;
    localparam data_t PHY_START = 64'h0000_0000_8000_0000;
    localparam data_t PHY_SIZE = 64'h0000_0000_0040_0000;
    localparam data_t VM_START = 64'hffff_ffe0_0000_0000;
    localparam data_t PA2VA_OFFSET = VM_START - PHY_START;
    localparam data_t INST_PAGE_FAULT = 64'd12;
    localparam data_t LOAD_PAGE_FAULT = 64'd13;
    localparam data_t STORE_PAGE_FAULT = 64'd15;
    localparam int TLB_ENTRIES = 16;
    localparam int TLB_INDEX_BITS = 4;

    typedef enum logic [2:0] {
        S_IDLE,
        S_DIRECT,
        S_WALK_REQ,
        S_WALK_RESP,
        S_ACCESS,
        S_FAULT
    } state_t;

    state_t state, state_n;

    data_t req_vaddr;
    logic req_write;
    logic req_read;
    logic [1:0] level;
    data_t pte_addr;
    data_t leaf_pte;
    logic [1:0] leaf_level;
    logic req_direct;
    logic req_kernel_direct;

    logic [TLB_ENTRIES-1:0] tlb_valid;
    logic [26:0] tlb_vpn [TLB_ENTRIES];
    logic [43:0] tlb_root_ppn [TLB_ENTRIES];
    data_t tlb_pte [TLB_ENTRIES];
    logic [1:0] tlb_level [TLB_ENTRIES];

    wire core_read_req = core_ift.r_request_valid;
    wire core_write_req = core_ift.w_request_valid;
    wire core_req_valid = IS_INST ? core_read_req : (core_read_req | core_write_req);
    wire selected_write = (!IS_INST) & core_write_req;
    wire selected_read = IS_INST | core_read_req | !core_write_req;
    wire [63:0] selected_addr = selected_write ? core_ift.w_request_bits.waddr
                                                : core_ift.r_request_bits.raddr;
    wire sv39_enabled = (satp[63:60] == 4'h8) && (priv != PRIV_M);
    wire canonical_addr = (selected_addr[63:39] == {25{selected_addr[38]}});
    wire kernel_direct_access = sv39_enabled && (priv != PRIV_U) &&
                                (selected_addr >= VM_START) &&
                                (selected_addr < (VM_START + PHY_SIZE));
    wire direct_access = !sv39_enabled || kernel_direct_access;
    wire [26:0] selected_vpn = selected_addr[38:12];
    wire [TLB_INDEX_BITS-1:0] tlb_index = selected_vpn[TLB_INDEX_BITS-1:0];
    wire tlb_hit = sv39_enabled && !kernel_direct_access && canonical_addr &&
                   tlb_valid[tlb_index] &&
                   (tlb_vpn[tlb_index] == selected_vpn) &&
                   (tlb_root_ppn[tlb_index] == satp[43:0]);
    wire tlb_perm_fault = permission_fault(tlb_pte[tlb_index], selected_write,
                                           selected_read, IS_INST, priv);

    wire pte_req_fire = mem_ift.r_request_valid & mem_ift.r_request_ready;
    wire pte_reply_fire = mem_ift.r_reply_valid & mem_ift.r_reply_ready;
    wire final_r_reply_fire = mem_ift.r_reply_valid & mem_ift.r_reply_ready;
    wire final_w_reply_fire = mem_ift.w_reply_valid & mem_ift.w_reply_ready;
    wire final_reply_fire = req_write ? final_w_reply_fire : final_r_reply_fire;

    wire [8:0] vpn0 = req_vaddr[20:12];
    wire [8:0] vpn1 = req_vaddr[29:21];
    wire [8:0] vpn2 = req_vaddr[38:30];

    function automatic [8:0] vpn_at(input data_t va, input logic [1:0] lvl);
        case (lvl)
            2'd2: vpn_at = va[38:30];
            2'd1: vpn_at = va[29:21];
            default: vpn_at = va[20:12];
        endcase
    endfunction

    function automatic data_t pte_table_addr(input logic [43:0] ppn, input data_t va, input logic [1:0] lvl);
        pte_table_addr = {8'b0, ppn[43:0], 12'b0} + {52'b0, vpn_at(va, lvl), 3'b0};
    endfunction

    function automatic logic pte_is_invalid(input data_t pte);
        pte_is_invalid = !pte[0] || (!pte[1] && pte[2]);
    endfunction

    function automatic logic pte_is_leaf(input data_t pte);
        pte_is_leaf = pte[1] || pte[3];
    endfunction

    function automatic logic superpage_misaligned(input data_t pte, input logic [1:0] lvl);
        case (lvl)
            2'd2: superpage_misaligned = |pte[27:10];
            2'd1: superpage_misaligned = |pte[18:10];
            default: superpage_misaligned = 1'b0;
        endcase
    endfunction

    function automatic data_t translated_addr(input data_t pte, input logic [1:0] lvl, input data_t va);
        case (lvl)
            2'd2: translated_addr = {8'b0, pte[53:28], va[29:0]};
            2'd1: translated_addr = {8'b0, pte[53:19], va[20:0]};
            default: translated_addr = {8'b0, pte[53:10], va[11:0]};
        endcase
    endfunction

    function automatic logic permission_fault(
        input data_t pte,
        input logic is_write,
        input logic is_read,
        input logic is_inst,
        input logic [1:0] cur_priv
    );
        logic allow;
        begin
            if (is_inst) begin
                allow = pte[3];
            end else if (is_write) begin
                allow = pte[2];
            end else if (is_read) begin
                allow = pte[1];
            end else begin
                allow = 1'b1;
            end

            permission_fault = !allow || ((cur_priv == PRIV_U) && !pte[4]);
        end
    endfunction

    wire [63:0] current_pte = mem_ift.r_reply_bits.rdata;
    wire current_pte_invalid = pte_is_invalid(current_pte);
    wire current_pte_leaf = pte_is_leaf(current_pte);
    wire current_perm_fault = permission_fault(current_pte, req_write, req_read, IS_INST, priv);
    wire current_superpage_fault = superpage_misaligned(current_pte, level);
    wire current_pte_fault = current_pte_invalid ||
                             (current_pte_leaf && (current_perm_fault || current_superpage_fault)) ||
                             (!current_pte_leaf && (level == 2'd0));

    wire [63:0] next_pte_addr = pte_table_addr(current_pte[53:10], req_vaddr, level - 2'd1);
    wire [63:0] final_paddr = req_kernel_direct ? (req_vaddr - PA2VA_OFFSET) :
                               (req_direct ? req_vaddr : translated_addr(leaf_pte, leaf_level, req_vaddr));

    always_comb begin
        state_n = state;
        unique case (state)
            S_IDLE: begin
                if (core_req_valid) begin
                    if (direct_access) begin
                        state_n = S_DIRECT;
                    end else if (!canonical_addr) begin
                        state_n = S_FAULT;
                    end else if (tlb_hit) begin
                        state_n = tlb_perm_fault ? S_FAULT : S_ACCESS;
                    end else begin
                        state_n = S_WALK_REQ;
                    end
                end
            end
            S_DIRECT: begin
                if (final_reply_fire) begin
                    state_n = S_IDLE;
                end
            end
            S_WALK_REQ: begin
                if (pte_req_fire) begin
                    state_n = S_WALK_RESP;
                end
            end
            S_WALK_RESP: begin
                if (pte_reply_fire) begin
                    if (current_pte_fault) begin
                        state_n = S_FAULT;
                    end else if (current_pte_leaf) begin
                        state_n = S_ACCESS;
                    end else begin
                        state_n = S_WALK_REQ;
                    end
                end
            end
            S_ACCESS: begin
                if (final_reply_fire) begin
                    state_n = S_IDLE;
                end
            end
            S_FAULT: begin
                if (switch_mode) begin
                    state_n = S_IDLE;
                end
            end
            default: state_n = S_IDLE;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst || switch_mode) begin
            state <= S_IDLE;
            req_vaddr <= 64'b0;
            req_write <= 1'b0;
            req_read <= 1'b0;
            level <= 2'd2;
            pte_addr <= 64'b0;
            leaf_pte <= 64'b0;
            leaf_level <= 2'd0;
            req_direct <= 1'b0;
            req_kernel_direct <= 1'b0;
            tlb_valid <= '0;
        end else begin
            state <= state_n;

            if (state == S_IDLE && core_req_valid) begin
                req_vaddr <= selected_addr;
                req_write <= selected_write;
                req_read <= selected_read;
                req_direct <= direct_access;
                req_kernel_direct <= kernel_direct_access;
                level <= 2'd2;
                pte_addr <= pte_table_addr(satp[43:0], selected_addr, 2'd2);
                if (tlb_hit && !tlb_perm_fault) begin
                    leaf_pte <= tlb_pte[tlb_index];
                    leaf_level <= tlb_level[tlb_index];
                end
            end else if (state == S_WALK_RESP && pte_reply_fire && !current_pte_fault) begin
                if (current_pte_leaf) begin
                    leaf_pte <= current_pte;
                    leaf_level <= level;
                    tlb_valid[req_vaddr[15:12]] <= 1'b1;
                    tlb_vpn[req_vaddr[15:12]] <= req_vaddr[38:12];
                    tlb_root_ppn[req_vaddr[15:12]] <= satp[43:0];
                    tlb_pte[req_vaddr[15:12]] <= current_pte;
                    tlb_level[req_vaddr[15:12]] <= level;
                end else begin
                    level <= level - 2'd1;
                    pte_addr <= next_pte_addr;
                end
            end
        end
    end

    always_comb begin
        core_ift.r_request_ready = 1'b0;
        core_ift.r_reply_valid = 1'b0;
        core_ift.r_reply_bits.rdata = 64'b0;
        core_ift.r_reply_bits.rresp = 2'b0;
        core_ift.w_request_ready = 1'b0;
        core_ift.w_reply_valid = 1'b0;
        core_ift.w_reply_bits.bresp = 2'b0;

        mem_ift.r_request_valid = 1'b0;
        mem_ift.r_request_bits.raddr = 64'b0;
        mem_ift.r_reply_ready = 1'b0;
        mem_ift.w_request_valid = 1'b0;
        mem_ift.w_request_bits.waddr = 64'b0;
        mem_ift.w_request_bits.wdata = 64'b0;
        mem_ift.w_request_bits.wmask = 8'b0;
        mem_ift.w_reply_ready = 1'b0;

        unique case (state)
            S_DIRECT, S_ACCESS: begin
                if (req_write) begin
                    mem_ift.w_request_valid = core_ift.w_request_valid;
                    mem_ift.w_request_bits = core_ift.w_request_bits;
                    mem_ift.w_request_bits.waddr = final_paddr;
                    core_ift.w_request_ready = mem_ift.w_request_ready;

                    mem_ift.w_reply_ready = core_ift.w_reply_ready;
                    core_ift.w_reply_valid = mem_ift.w_reply_valid;
                    core_ift.w_reply_bits = mem_ift.w_reply_bits;
                end else begin
                    mem_ift.r_request_valid = core_ift.r_request_valid;
                    mem_ift.r_request_bits = core_ift.r_request_bits;
                    mem_ift.r_request_bits.raddr = final_paddr;
                    core_ift.r_request_ready = mem_ift.r_request_ready;

                    mem_ift.r_reply_ready = core_ift.r_reply_ready;
                    core_ift.r_reply_valid = mem_ift.r_reply_valid;
                    core_ift.r_reply_bits = mem_ift.r_reply_bits;
                end
            end
            S_WALK_REQ: begin
                mem_ift.r_request_valid = 1'b1;
                mem_ift.r_request_bits.raddr = pte_addr;
            end
            S_WALK_RESP: begin
                mem_ift.r_reply_ready = 1'b1;
            end
            default: begin
            end
        endcase
    end

    always_comb begin
        except_mmu = '{default:'0};
        if (state == S_FAULT) begin
            except_mmu.except = 1'b1;
            except_mmu.epc = pc_fault;
            except_mmu.ecause = IS_INST ? INST_PAGE_FAULT :
                                (req_write ? STORE_PAGE_FAULT : LOAD_PAGE_FAULT);
            except_mmu.etval = req_vaddr;
        end
    end

endmodule
