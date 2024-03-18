// ******************************************************************
// Wrapper for the PULP Ara RVV accelerator and CVA6 core.
// ******************************************************************

module ARACoreBlackbox import axi_pkg::*; import ara_pkg::*;
#(
  parameter TRACEPORT_SZ = 64,
  parameter XLEN = 64,
  parameter HARTID_LEN = 64,
  parameter RAS_ENTRIES = 4,
  parameter BTB_ENTRIES = 16,
  parameter BHT_ENTRIES = 16,
  parameter [63:0] EXEC_REG_CNT = 5,
  parameter [63:0] EXEC_REG_BASE_0 = 0,
  parameter [63:0] EXEC_REG_SZ_0 = 64,
  parameter [63:0] EXEC_REG_BASE_1 = 1024,
  parameter [63:0] EXEC_REG_SZ_1 = 64,
  parameter [63:0] EXEC_REG_BASE_2 = 2048,
  parameter [63:0] EXEC_REG_SZ_2 = 64,
  parameter [63:0] EXEC_REG_BASE_3 = 4096,
  parameter [63:0] EXEC_REG_SZ_3 = 0,
  parameter [63:0] EXEC_REG_BASE_4 = 0,
  parameter [63:0] EXEC_REG_SZ_4 = 0,
  parameter [63:0] CACHE_REG_CNT = 1,
  parameter [63:0] CACHE_REG_BASE_0 = 10240,
  parameter [63:0] CACHE_REG_SZ_0 = 1024,
  parameter [63:0] CACHE_REG_BASE_1 = 0,
  parameter [63:0] CACHE_REG_SZ_1 = 0,
  parameter [63:0] CACHE_REG_BASE_2 = 0,
  parameter [63:0] CACHE_REG_SZ_2 = 0,
  parameter [63:0] CACHE_REG_BASE_3 = 0,
  parameter [63:0] CACHE_REG_SZ_3 = 0,
  parameter [63:0] CACHE_REG_BASE_4 = 0,
  parameter [63:0] CACHE_REG_SZ_4 = 0,
  parameter [63:0] DEBUG_BASE = 0,
  parameter AXI_ADDRESS_WIDTH = 64,
  parameter AXI_DATA_WIDTH = 64,
  parameter AXI_NARROW_DATA_WIDTH = 64,
  parameter AXI_USER_WIDTH = 1,
  parameter AXI_ID_WIDTH = 4,
  parameter PMP_ENTRIES = 4,
  parameter NR_LANES = AXI_DATA_WIDTH/64*2
) (
  input clk_i,
  input rst_ni,
  input [XLEN - 1:0] boot_addr_i,
  input [HARTID_LEN - 1:0] hart_id_i,
  input [1:0] irq_i,
  input ipi_i,
  input time_irq_i,
  input debug_req_i,
  output [TRACEPORT_SZ-1:0] trace_o,

  input  axi_resp_i_aw_ready,
  output axi_req_o_aw_valid,
  output [AXI_ID_WIDTH-1:0] axi_req_o_aw_bits_id,
  output [AXI_ADDRESS_WIDTH-1:0] axi_req_o_aw_bits_addr,
  output [7:0] axi_req_o_aw_bits_len,
  output [2:0] axi_req_o_aw_bits_size,
  output [1:0] axi_req_o_aw_bits_burst,
  output axi_req_o_aw_bits_lock,
  output [3:0] axi_req_o_aw_bits_cache,
  output [2:0] axi_req_o_aw_bits_prot,
  output [3:0] axi_req_o_aw_bits_qos,
  output [3:0] axi_req_o_aw_bits_region,
  output [5:0] axi_req_o_aw_bits_atop,
  output [AXI_USER_WIDTH-1:0] axi_req_o_aw_bits_user,

  input axi_resp_i_w_ready,
  output axi_req_o_w_valid,
  output [AXI_DATA_WIDTH-1:0] axi_req_o_w_bits_data,
  output [(AXI_DATA_WIDTH/8)-1:0] axi_req_o_w_bits_strb,
  output axi_req_o_w_bits_last,
  output [AXI_USER_WIDTH-1:0] axi_req_o_w_bits_user,

  input axi_resp_i_ar_ready,
  output axi_req_o_ar_valid,
  output [AXI_ID_WIDTH-1:0] axi_req_o_ar_bits_id,
  output [AXI_ADDRESS_WIDTH-1:0] axi_req_o_ar_bits_addr,
  output [7:0] axi_req_o_ar_bits_len,
  output [2:0] axi_req_o_ar_bits_size,
  output [1:0] axi_req_o_ar_bits_burst,
  output axi_req_o_ar_bits_lock,
  output [3:0] axi_req_o_ar_bits_cache,
  output [2:0] axi_req_o_ar_bits_prot,
  output [3:0] axi_req_o_ar_bits_qos,
  output [3:0] axi_req_o_ar_bits_region,
  output [AXI_USER_WIDTH-1:0] axi_req_o_ar_bits_user,

  output axi_req_o_b_ready,
  input axi_resp_i_b_valid,
  input [AXI_ID_WIDTH-1:0] axi_resp_i_b_bits_id,
  input [1:0] axi_resp_i_b_bits_resp,
  input [AXI_USER_WIDTH-1:0] axi_resp_i_b_bits_user,

  output axi_req_o_r_ready,
  input axi_resp_i_r_valid,
  input [AXI_ID_WIDTH-1:0] axi_resp_i_r_bits_id,
  input [AXI_DATA_WIDTH-1:0] axi_resp_i_r_bits_data,
  input [1:0] axi_resp_i_r_bits_resp,
  input axi_resp_i_r_bits_last,
  input [AXI_USER_WIDTH-1:0] axi_resp_i_r_bits_user
);

  localparam ariane_pkg::ariane_cfg_t CVA6SocCfg = '{
    RASDepth:              RAS_ENTRIES,
    BTBEntries:            BTB_ENTRIES,
    BHTEntries:            BHT_ENTRIES,
    // idempotent region
    NrNonIdempotentRules:  0,
    NonIdempotentAddrBase: {64'b0},
    NonIdempotentLength:   {64'b0},
    // execute region
    NrExecuteRegionRules:  EXEC_REG_CNT,
    ExecuteRegionAddrBase: {EXEC_REG_BASE_4, EXEC_REG_BASE_3, EXEC_REG_BASE_2, EXEC_REG_BASE_1, EXEC_REG_BASE_0},
    ExecuteRegionLength:   {  EXEC_REG_SZ_4,   EXEC_REG_SZ_3,   EXEC_REG_SZ_2,   EXEC_REG_SZ_1,   EXEC_REG_SZ_0},
    // cached region
    NrCachedRegionRules:   CACHE_REG_CNT,
    CachedRegionAddrBase:  {CACHE_REG_BASE_4, CACHE_REG_BASE_3, CACHE_REG_BASE_2, CACHE_REG_BASE_1, CACHE_REG_BASE_0},
    CachedRegionLength:    {  CACHE_REG_SZ_4,   CACHE_REG_SZ_3,   CACHE_REG_SZ_2,   CACHE_REG_SZ_1,   CACHE_REG_SZ_0},
    //  cache config
    AxiCompliant:          1'b1,
    SwapEndianess:         1'b0,
    // debug
    DmBaseAddress:         DEBUG_BASE,
    NrPMPEntries:          PMP_ENTRIES
  };


  ///////////
  //  AXI  //
  ///////////

  localparam AXI_INNER_ID_WIDTH = AXI_ID_WIDTH-1;

  typedef logic [AXI_DATA_WIDTH-1:0] axi_data_t;
  typedef logic [AXI_DATA_WIDTH/8-1:0] axi_strb_t;
  typedef logic [AXI_ADDRESS_WIDTH-1:0] axi_addr_t;
  typedef logic [AXI_USER_WIDTH-1:0] axi_user_t;
  typedef logic [AXI_ID_WIDTH-1:0] axi_outer_id_t;
  typedef logic [AXI_INNER_ID_WIDTH-1:0] axi_inner_id_t;

  // AXI Typedefs
  `AXI_TYPEDEF_ALL(inner_axi, axi_addr_t, axi_inner_id_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(system_axi, axi_addr_t, axi_outer_id_t, axi_data_t, axi_strb_t, axi_user_t)

  inner_axi_req_t    cva6_axi_req, ara_axi_req_inval, ara_axi_req;
  inner_axi_resp_t   cva6_axi_resp, ara_axi_resp_inval, ara_axi_resp;
  system_axi_req_t   system_axi_req;
  system_axi_resp_t  system_axi_resp;

  ////////////////////
  //  Ara and CVA6  //
  ////////////////////

  import acc_pkg::accelerator_req_t;
  import acc_pkg::accelerator_resp_t;


  // Accelerator MMU ports
  logic                   en_ld_st_translation;
  ariane_pkg::exception_t acc_mmu_misaligned_ex;
  logic                   acc_mmu_req;
  logic [riscv::VLEN-1:0] acc_mmu_vaddr;
  logic                   acc_mmu_is_store;
  logic                   acc_mmu_dtlb_hit;
  logic [riscv::PPNW-1:0] acc_mmu_dtlb_ppn;
  logic                   acc_mmu_valid;
  logic [riscv::PLEN-1:0] acc_mmu_paddr;
  ariane_pkg::exception_t acc_mmu_exception;

  // Accelerator ports
  accelerator_req_t             acc_req;
  accelerator_resp_t            acc_resp;
  logic                         acc_cons_en;
  logic [AXI_ADDRESS_WIDTH-1:0] inval_addr;
  logic                         inval_valid;
  logic                         inval_ready;

  traced_instr_pkg::trace_port_t tp_if;

  // Roll all trace signals into a single bit array (and pack according to rocket-chip).
  for (genvar i = 0; i < ariane_pkg::NR_COMMIT_PORTS; ++i) begin : gen_tp_roll
    assign trace_o[(TRACEPORT_SZ*(i+1)/ariane_pkg::NR_COMMIT_PORTS)-1:(TRACEPORT_SZ*i/ariane_pkg::NR_COMMIT_PORTS)] = {
      tp_if[i].tval[39:0],
      tp_if[i].cause[7:0],
      tp_if[i].interrupt,
      tp_if[i].exception,
      { 1'b0, tp_if[i].priv[1:0] },
      tp_if[i].insn[31:0],
      tp_if[i].iaddr[39:0],
      tp_if[i].valid,
      ~tp_if[i].reset,
      tp_if[i].clock
    };
  end

  cva6 #(
    .ArianeCfg    (CVA6SocCfg                 ),
    .cvxif_req_t  (acc_pkg::accelerator_req_t ),
    .cvxif_resp_t (acc_pkg::accelerator_resp_t),
    .AxiAddrWidth (AXI_ADDRESS_WIDTH          ),
    .AxiDataWidth (AXI_DATA_WIDTH             ),
    .AxiIdWidth   (AXI_INNER_ID_WIDTH         ),
    .axi_ar_chan_t(inner_axi_ar_chan_t        ),
    .axi_aw_chan_t(inner_axi_aw_chan_t        ),
    .axi_w_chan_t (inner_axi_w_chan_t         ),
    .axi_req_t    (inner_axi_req_t            ),
    .axi_rsp_t    (inner_axi_resp_t           )
  ) i_cva6 (
    .clk_i,
    .rst_ni,
    .boot_addr_i,
    .hart_id_i,
    .irq_i,
    .ipi_i,
    .time_irq_i,
    .debug_req_i,
    // Invalidation requests
    .acc_cons_en_o(acc_cons_en),
    .inval_addr_i (inval_addr ),
    .inval_valid_i(inval_valid),
    .inval_ready_o(inval_ready),
    // Accelerator MMU interface
    .en_ld_st_translation_o (en_ld_st_translation ),
    .acc_mmu_misaligned_ex_i(acc_mmu_misaligned_ex),
    .acc_mmu_req_i          (acc_mmu_req          ),
    .acc_mmu_vaddr_i        (acc_mmu_vaddr        ),
    .acc_mmu_is_store_i     (acc_mmu_is_store     ),
    .acc_mmu_dtlb_hit_o     (acc_mmu_dtlb_hit     ),
    .acc_mmu_dtlb_ppn_o     (acc_mmu_dtlb_ppn     ),
    .acc_mmu_valid_o        (acc_mmu_valid        ),
    .acc_mmu_paddr_o        (acc_mmu_paddr        ),
    .acc_mmu_exception_o    (acc_mmu_exception    ),
    // Tracer interfaces
    .rvfi_o(),
    .trace_o(tp_if),
    // Accelerator ports
    .cvxif_req_o (acc_req ),
    .cvxif_resp_i(acc_resp),
    // L15
    .l15_req_o (  ),
    .l15_rtrn_i('0),
    // Memory interface
    .axi_req_o (cva6_axi_req ),
    .axi_resp_i(cva6_axi_resp)
  );

  axi_inval_filter #(
    .MaxTxns    (4                              ),
    .AddrWidth  (AXI_ADDRESS_WIDTH              ),
    .L1LineWidth(ariane_pkg::DCACHE_LINE_WIDTH/8),
    .aw_chan_t  (inner_axi_aw_chan_t            ),
    .req_t      (inner_axi_req_t                ),
    .resp_t     (inner_axi_resp_t               )
  ) i_axi_inval_filter (
    .clk_i,
    .rst_ni,
    .en_i         (acc_cons_en       ),
    .slv_req_i    (ara_axi_req       ),
    .slv_resp_o   (ara_axi_resp      ),
    .mst_req_o    (ara_axi_req_inval ),
    .mst_resp_i   (ara_axi_resp_inval),
    .inval_addr_o (inval_addr        ),
    .inval_valid_o(inval_valid       ),
    .inval_ready_i(inval_ready       )
  );

  ara #(
    .NrLanes     (NR_LANES          ),
    .FPUSupport  (FPUSupportHalfSingleDouble),
    .FPExtSupport(FPExtSupportEnable),
    .FixPtSupport(FixedPointEnable  ),
    .AxiDataWidth(AXI_DATA_WIDTH    ),
    .AxiAddrWidth(AXI_ADDRESS_WIDTH ),
    .axi_ar_t    (inner_axi_ar_chan_t),
    .axi_r_t     (inner_axi_r_chan_t ),
    .axi_aw_t    (inner_axi_aw_chan_t),
    .axi_w_t     (inner_axi_w_chan_t ),
    .axi_b_t     (inner_axi_b_chan_t ),
    .axi_req_t   (inner_axi_req_t    ),
    .axi_resp_t  (inner_axi_resp_t   )
  ) i_ara (
    .clk_i,
    .rst_ni,
    .scan_enable_i         (1'b0                 ),
    .scan_data_i           (1'b0                 ),
    .scan_data_o           (                     ),
    .en_ld_st_translation_i(en_ld_st_translation ),
    .mmu_misaligned_ex_o   (acc_mmu_misaligned_ex),
    .mmu_req_o             (acc_mmu_req          ),
    .mmu_vaddr_o           (acc_mmu_vaddr        ),
    .mmu_is_store_o        (acc_mmu_is_store     ),
    .mmu_dtlb_hit_i        (acc_mmu_dtlb_hit     ),
    .mmu_dtlb_ppn_i        (acc_mmu_dtlb_ppn     ),
    .mmu_valid_i           (acc_mmu_valid        ),
    .mmu_paddr_i           (acc_mmu_paddr        ),
    .mmu_exception_i       (acc_mmu_exception    ),
    .acc_req_i             (acc_req              ),
    .acc_resp_o            (acc_resp             ),
    .axi_req_o             (ara_axi_req          ),
    .axi_resp_i            (ara_axi_resp         )
  );

  axi_mux #(
    .SlvAxiIDWidth(AXI_INNER_ID_WIDTH  ),
    .slv_ar_chan_t(inner_axi_ar_chan_t ),
    .slv_aw_chan_t(inner_axi_aw_chan_t ),
    .slv_b_chan_t (inner_axi_b_chan_t  ),
    .slv_r_chan_t (inner_axi_r_chan_t  ),
    .slv_req_t    (inner_axi_req_t     ),
    .slv_resp_t   (inner_axi_resp_t    ),
    .mst_ar_chan_t(system_axi_ar_chan_t),
    .mst_aw_chan_t(system_axi_aw_chan_t),
    .w_chan_t     (system_axi_w_chan_t ),
    .mst_b_chan_t (system_axi_b_chan_t ),
    .mst_r_chan_t (system_axi_r_chan_t ),
    .mst_req_t    (system_axi_req_t    ),
    .mst_resp_t   (system_axi_resp_t   ),
    .NoSlvPorts   (2                   ),
    .SpillAr      (1'b1                ),
    .SpillR       (1'b1                ),
    .SpillAw      (1'b1                ),
    .SpillW       (1'b1                ),
    .SpillB       (1'b1                )
  ) i_system_mux (
    .clk_i,
    .rst_ni,
    .test_i     (1'b0                               ),
    .slv_reqs_i ({ara_axi_req_inval,  cva6_axi_req} ),
    .slv_resps_o({ara_axi_resp_inval, cva6_axi_resp}),
    .mst_req_o  (system_axi_req                     ),
    .mst_resp_i (system_axi_resp                    )
  );

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH   ),
    .AXI_ID_WIDTH  (AXI_ID_WIDTH     ),
    .AXI_USER_WIDTH(AXI_USER_WIDTH   )
  ) system_axi_bus();

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH   ),
    .AXI_ID_WIDTH  (AXI_ID_WIDTH     ),
    .AXI_USER_WIDTH(AXI_USER_WIDTH   )
  ) outer_axi_bus();

  // convert ariane axi port to normal axi port
  assign system_axi_bus.aw_id      = system_axi_req.aw.id;
  assign system_axi_bus.aw_addr    = system_axi_req.aw.addr;
  assign system_axi_bus.aw_len     = system_axi_req.aw.len;
  assign system_axi_bus.aw_size    = system_axi_req.aw.size;
  assign system_axi_bus.aw_burst   = system_axi_req.aw.burst;
  assign system_axi_bus.aw_lock    = system_axi_req.aw.lock;
  assign system_axi_bus.aw_cache   = system_axi_req.aw.cache;
  assign system_axi_bus.aw_prot    = system_axi_req.aw.prot;
  assign system_axi_bus.aw_qos     = system_axi_req.aw.qos;
  assign system_axi_bus.aw_atop    = system_axi_req.aw.atop;
  assign system_axi_bus.aw_region  = system_axi_req.aw.region;
  assign system_axi_bus.aw_user    = system_axi_req.aw.user;
  assign system_axi_bus.aw_valid   = system_axi_req.aw_valid;
  assign system_axi_resp.aw_ready  = system_axi_bus.aw_ready;

  assign system_axi_bus.w_data     = system_axi_req.w.data;
  assign system_axi_bus.w_strb     = system_axi_req.w.strb;
  assign system_axi_bus.w_last     = system_axi_req.w.last;
  assign system_axi_bus.w_user     = system_axi_req.w.user;
  assign system_axi_bus.w_valid    = system_axi_req.w_valid;
  assign system_axi_resp.w_ready   = system_axi_bus.w_ready;

  assign system_axi_resp.b.id      = system_axi_bus.b_id;
  assign system_axi_resp.b.resp    = system_axi_bus.b_resp;
  assign system_axi_resp.b_valid   = system_axi_bus.b_valid;
  assign system_axi_bus.b_ready    = system_axi_req.b_ready;

  assign system_axi_bus.ar_id      = system_axi_req.ar.id;
  assign system_axi_bus.ar_addr    = system_axi_req.ar.addr;
  assign system_axi_bus.ar_len     = system_axi_req.ar.len;
  assign system_axi_bus.ar_size    = system_axi_req.ar.size;
  assign system_axi_bus.ar_burst   = system_axi_req.ar.burst;
  assign system_axi_bus.ar_lock    = system_axi_req.ar.lock;
  assign system_axi_bus.ar_cache   = system_axi_req.ar.cache;
  assign system_axi_bus.ar_prot    = system_axi_req.ar.prot;
  assign system_axi_bus.ar_qos     = system_axi_req.ar.qos;
  assign system_axi_bus.ar_region  = system_axi_req.ar.region;
  assign system_axi_bus.ar_user    = system_axi_req.ar.user;
  assign system_axi_bus.ar_valid   = system_axi_req.ar_valid;
  assign system_axi_resp.ar_ready  = system_axi_bus.ar_ready;

  assign system_axi_resp.r.id      = system_axi_bus.r_id;
  assign system_axi_resp.r.data    = system_axi_bus.r_data;
  assign system_axi_resp.r.resp    = system_axi_bus.r_resp;
  assign system_axi_resp.r.last    = system_axi_bus.r_last;
  assign system_axi_resp.r_valid   = system_axi_bus.r_valid;
  assign system_axi_bus.r_ready    = system_axi_req.r_ready;

  // deal with atomics using arianes wrapper
  axi_riscv_atomics_wrap #(
    .AXI_ADDR_WIDTH    (AXI_ADDRESS_WIDTH),
    .AXI_DATA_WIDTH    (AXI_DATA_WIDTH   ),
    .AXI_ID_WIDTH      (AXI_ID_WIDTH     ),
    .AXI_USER_WIDTH    (AXI_USER_WIDTH   ),
    .AXI_MAX_WRITE_TXNS(1                ),
    .RISCV_WORD_WIDTH  (XLEN             )
  ) i_axi_riscv_atomics (
    .clk_i,
    .rst_ni,
    .slv(system_axi_bus),
    .mst(outer_axi_bus)
  );

  // Connect outer_axi_bus to the top-level signals.
  assign outer_axi_bus.aw_ready   = axi_resp_i_aw_ready;
  assign axi_req_o_aw_valid       = outer_axi_bus.aw_valid;
  assign axi_req_o_aw_bits_id     = outer_axi_bus.aw_id;
  assign axi_req_o_aw_bits_addr   = outer_axi_bus.aw_addr;
  assign axi_req_o_aw_bits_len    = outer_axi_bus.aw_len;
  assign axi_req_o_aw_bits_size   = outer_axi_bus.aw_size;
  assign axi_req_o_aw_bits_burst  = outer_axi_bus.aw_burst;
  assign axi_req_o_aw_bits_lock   = outer_axi_bus.aw_lock;
  assign axi_req_o_aw_bits_cache  = outer_axi_bus.aw_cache;
  assign axi_req_o_aw_bits_prot   = outer_axi_bus.aw_prot;
  assign axi_req_o_aw_bits_qos    = outer_axi_bus.aw_qos;
  assign axi_req_o_aw_bits_region = outer_axi_bus.aw_region;
  assign axi_req_o_aw_bits_atop   = outer_axi_bus.aw_atop;
  assign axi_req_o_aw_bits_user   = outer_axi_bus.aw_user;

  assign outer_axi_bus.w_ready    = axi_resp_i_w_ready;
  assign axi_req_o_w_valid        = outer_axi_bus.w_valid;
  assign axi_req_o_w_bits_data    = outer_axi_bus.w_data;
  assign axi_req_o_w_bits_strb    = outer_axi_bus.w_strb;
  assign axi_req_o_w_bits_last    = outer_axi_bus.w_last;
  assign axi_req_o_w_bits_user    = outer_axi_bus.w_user;

  assign outer_axi_bus.ar_ready   = axi_resp_i_ar_ready;
  assign axi_req_o_ar_valid       = outer_axi_bus.ar_valid;
  assign axi_req_o_ar_bits_id     = outer_axi_bus.ar_id;
  assign axi_req_o_ar_bits_addr   = outer_axi_bus.ar_addr;
  assign axi_req_o_ar_bits_len    = outer_axi_bus.ar_len;
  assign axi_req_o_ar_bits_size   = outer_axi_bus.ar_size;
  assign axi_req_o_ar_bits_burst  = outer_axi_bus.ar_burst;
  assign axi_req_o_ar_bits_lock   = outer_axi_bus.ar_lock;
  assign axi_req_o_ar_bits_cache  = outer_axi_bus.ar_cache;
  assign axi_req_o_ar_bits_prot   = outer_axi_bus.ar_prot;
  assign axi_req_o_ar_bits_qos    = outer_axi_bus.ar_qos;
  assign axi_req_o_ar_bits_region = outer_axi_bus.ar_region;
  assign axi_req_o_ar_bits_user   = outer_axi_bus.ar_user;

  assign axi_req_o_b_ready        = outer_axi_bus.b_ready;
  assign outer_axi_bus.b_valid    = axi_resp_i_b_valid;
  assign outer_axi_bus.b_id       = axi_resp_i_b_bits_id;
  assign outer_axi_bus.b_resp     = axi_resp_i_b_bits_resp;
  assign outer_axi_bus.b_user     = axi_resp_i_b_bits_user;

  assign axi_req_o_r_ready        = outer_axi_bus.r_ready;
  assign outer_axi_bus.r_valid    = axi_resp_i_r_valid;
  assign outer_axi_bus.r_id       = axi_resp_i_r_bits_id;
  assign outer_axi_bus.r_data     = axi_resp_i_r_bits_data;
  assign outer_axi_bus.r_resp     = axi_resp_i_r_bits_resp;
  assign outer_axi_bus.r_last     = axi_resp_i_r_bits_last;
  assign outer_axi_bus.r_user     = axi_resp_i_r_bits_user;

endmodule
