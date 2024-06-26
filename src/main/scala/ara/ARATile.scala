//******************************************************************************
// Copyright (c) 2019 - 2019, The Regents of the University of California (Regents).
// All Rights Reserved. See LICENSE and LICENSE.SiFive for license details.
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// ARA Tile Wrapper
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

package ara

import chisel3._
import chisel3.util._
import chisel3.experimental.{IntParam, StringParam}

import scala.collection.mutable.{ListBuffer}

import org.chipsalliance.cde.config._
import freechips.rocketchip.subsystem._
import freechips.rocketchip.devices.tilelink._
import freechips.rocketchip.diplomacy._

import freechips.rocketchip.rocket._
import freechips.rocketchip.subsystem.{RocketCrossingParams}
import freechips.rocketchip.tilelink._
import freechips.rocketchip.interrupts._
import freechips.rocketchip.util._
import freechips.rocketchip.tile._
import freechips.rocketchip.amba.axi4._
import freechips.rocketchip.prci.ClockSinkParameters

case class ARACoreParams(
  bootFreqHz: BigInt = BigInt(1700000000),
  rasEntries: Int = 4,
  btbEntries: Int = 16,
  bhtEntries: Int = 16,
  pmpEntries: Int = 4,
  enableToFromHostCaching: Boolean = false,
) extends CoreParams {
  /* DO NOT CHANGE BELOW THIS */
  val useVM: Boolean = true
  val useHypervisor: Boolean = false
  val useUser: Boolean = true
  val useSupervisor: Boolean = false
  val useDebug: Boolean = true
  val useAtomics: Boolean = true
  val useAtomicsOnlyForIO: Boolean = false // copied from Rocket
  val useCompressed: Boolean = true
  val useSCIE: Boolean = false
  val useRVE: Boolean = false
  val mulDiv: Option[MulDivParams] = Some(MulDivParams()) // copied from Rocket
  val fpu: Option[FPUParams] = Some(FPUParams()) // copied fma latencies from Rocket
  val nLocalInterrupts: Int = 0
  val useNMI: Boolean = false
  val nPMPs: Int = 0 // TODO: Check
  val pmpGranularity: Int = 4 // copied from Rocket
  val nBreakpoints: Int = 0 // TODO: Check
  val useBPWatch: Boolean = false
  val mcontextWidth: Int = 0 // TODO: Check
  val scontextWidth: Int = 0 // TODO: Check
  val nPerfCounters: Int = 29
  val haveBasicCounters: Boolean = true
  val haveFSDirty: Boolean = false
  val misaWritable: Boolean = false
  val haveCFlush: Boolean = false
  val nL2TLBEntries: Int = 512 // copied from Rocket
  val nL2TLBWays: Int = 1
  val mtvecInit: Option[BigInt] = Some(BigInt(0)) // copied from Rocket
  val mtvecWritable: Boolean = true // copied from Rocket
  val instBits: Int = if (useCompressed) 16 else 32
  val lrscCycles: Int = 80 // copied from Rocket
  val decodeWidth: Int = 1 // TODO: Check
  val fetchWidth: Int = 1 // TODO: Check
  val retireWidth: Int = 2
  val nPTECacheEntries: Int = 8 // TODO: Check
  val useBitManip: Boolean = false
  val useBitManipCrypto: Boolean = false
  val useCryptoNIST: Boolean = false
  val useCryptoSM: Boolean = false
  val traceHasWdata: Boolean = false
  val useConditionalZero: Boolean = false

  override val useVector: Boolean = true
  override def vLen: Int = 2048
  override def vMemDataBits: Int = 64
}

case class ARATileAttachParams(
  tileParams: ARATileParams,
  crossingParams: RocketCrossingParams
) extends CanAttachTile {
  type TileType = ARATile
  val lookup = PriorityMuxHartIdFromSeq(Seq(tileParams))
}

// TODO: BTBParams, DCacheParams, ICacheParams are incorrect in DTB... figure out defaults in ARA and put in DTB
case class ARATileParams(
  name: Option[String] = Some("ara_tile"),
  tileId: Int = 0,
  trace: Boolean = false,
  val core: ARACoreParams = ARACoreParams()
) extends InstantiableTileParams[ARATile]
{
  val beuAddr: Option[BigInt] = None
  val blockerCtrlAddr: Option[BigInt] = None
  val btb: Option[BTBParams] = Some(BTBParams())
  val boundaryBuffers: Boolean = false
  val dcache: Option[DCacheParams] = Some(DCacheParams())
  val icache: Option[ICacheParams] = Some(ICacheParams())
  val clockSinkParams: ClockSinkParameters = ClockSinkParameters()
  def instantiate(crossing: HierarchicalElementCrossingParamsLike, lookup: LookupByHartIdImpl)(implicit p: Parameters): ARATile = {
    new ARATile(this, crossing, lookup)
  }
  val baseName = name.getOrElse("ara_tile")
  val uniqueName = s"${baseName}_$tileId"
}

class ARATile private(
  val araParams: ARATileParams,
  crossing: ClockCrossingType,
  lookup: LookupByHartIdImpl,
  q: Parameters)
  extends BaseTile(araParams, crossing, lookup, q)
  with SinksExternalInterrupts
  with SourcesExternalNotifications
{
  /**
   * Setup parameters:
   * Private constructor ensures altered LazyModule.p is used implicitly
   */
  def this(params: ARATileParams, crossing: HierarchicalElementCrossingParamsLike, lookup: LookupByHartIdImpl)(implicit p: Parameters) =
    this(params, crossing.crossingType, lookup, p)

  val intOutwardNode = None
  val slaveNode = TLIdentityNode()
  val masterNode = visibilityNode

  tlOtherMastersNode := tlMasterXbar.node
  masterNode :=* tlOtherMastersNode
  DisableMonitors { implicit p => tlSlaveXbar.node :*= slaveNode }

  val cpuDevice: SimpleDevice = new SimpleDevice("cpu", Seq("pulp-platform,ara", "riscv")) {
    override def parent = Some(ResourceAnchors.cpus)
    override def describe(resources: ResourceBindings): Description = {
      val Description(name, mapping) = super.describe(resources)
      Description(name, mapping ++
                        cpuProperties ++
                        nextLevelCacheProperty ++
                        tileProperties)
    }
  }

  ResourceBinding {
    Resource(cpuDevice, "reg").bind(ResourceAddress(tileId))
  }

 override def makeMasterBoundaryBuffers(crossing: ClockCrossingType)(implicit p: Parameters) = crossing match {
    case _: RationalCrossing =>
      if (!araParams.boundaryBuffers) TLBuffer(BufferParams.none)
      else TLBuffer(BufferParams.none, BufferParams.flow, BufferParams.none, BufferParams.flow, BufferParams(1))
    case _ => TLBuffer(BufferParams.none)
  }

  override def makeSlaveBoundaryBuffers(crossing: ClockCrossingType)(implicit p: Parameters) = crossing match {
    case _: RationalCrossing =>
      if (!araParams.boundaryBuffers) TLBuffer(BufferParams.none)
      else TLBuffer(BufferParams.flow, BufferParams.none, BufferParams.none, BufferParams.none, BufferParams.none)
    case _ => TLBuffer(BufferParams.none)
  }

  override lazy val module = new ARATileModuleImp(this)

  /**
   * Setup AXI4 memory interface.
   * THESE ARE CONSTANTS.
   */
  val portName = "ara-mem-port-axi4"
  val idBits = 4
  val beatBytes = masterPortBeatBytes
  val sourceBits = 1 // equiv. to userBits (i think)

  val memAXI4Node = AXI4MasterNode(
    Seq(AXI4MasterPortParameters(
      masters = Seq(AXI4MasterParameters(
        name = portName,
        id = IdRange(0, 1 << idBits))))))

  val memoryTap = TLIdentityNode()
  (tlMasterXbar.node
    := memoryTap
    := TLBuffer()
    := TLFIFOFixer(TLFIFOFixer.all) // fix FIFO ordering
    := TLWidthWidget(beatBytes) // reduce size of TL
    := AXI4ToTL() // convert to TL
    := AXI4UserYanker(Some(2)) // remove user field on AXI interface. need but in reality user intf. not needed
    := AXI4Fragmenter() // deal with multi-beat xacts
    := memAXI4Node)

  def connectARAInterrupts(debug: Bool, msip: Bool, mtip: Bool, m_s_eip: UInt) : Unit = {
    val (interrupts, _) = intSinkNode.in(0)
    debug := interrupts(0)
    msip := interrupts(1)
    mtip := interrupts(2)
    m_s_eip := Cat(interrupts(4), interrupts(3))
  }
}

class ARATileModuleImp(outer: ARATile) extends BaseTileModuleImp(outer){
  // annotate the parameters
  Annotated.params(this, outer.araParams)

  val debugBaseAddr = BigInt(0x0) // CONSTANT: based on default debug module
  val debugSz = BigInt(0x1000) // CONSTANT: based on default debug module
  val tohostAddr = BigInt(0x80001000L) // CONSTANT: based on default sw (assume within extMem region)
  val fromhostAddr = BigInt(0x80001040L) // CONSTANT: based on default sw (assume within extMem region)

  // have the main memory, bootrom, debug regions be executable
  val bootromParams = p(BootROMLocated(InSubsystem)).get
  val executeRegionBases = Seq(p(ExtMem).get.master.base,      bootromParams.address, debugBaseAddr, BigInt(0x0), BigInt(0x0))
  val executeRegionSzs   = Seq(p(ExtMem).get.master.size, BigInt(bootromParams.size),       debugSz, BigInt(0x0), BigInt(0x0))
  val executeRegionCnt   = executeRegionBases.length

  // have the main memory be cached, but don't cache tohost/fromhost addresses
  // TODO: current cache subsystem can only support 1 cacheable region... so cache AFTER the tohost/fromhost addresses
  val wordOffset = 0x40
  val (cacheableRegionBases, cacheableRegionSzs) = if (outer.araParams.core.enableToFromHostCaching) {
    val bases = Seq(p(ExtMem).get.master.base, BigInt(0x0), BigInt(0x0), BigInt(0x0), BigInt(0x0))
    val sizes   = Seq(p(ExtMem).get.master.size, BigInt(0x0), BigInt(0x0), BigInt(0x0), BigInt(0x0))
    (bases, sizes)
  } else {
    val bases = Seq(                                                          fromhostAddr + 0x40,              p(ExtMem).get.master.base, BigInt(0x0), BigInt(0x0), BigInt(0x0))
    val sizes = Seq(p(ExtMem).get.master.size - (fromhostAddr + 0x40 - p(ExtMem).get.master.base), tohostAddr - p(ExtMem).get.master.base, BigInt(0x0), BigInt(0x0), BigInt(0x0))
    (bases, sizes)
  }
  val cacheableRegionCnt   = cacheableRegionBases.length

  // Add 2 to account for the extra clock and reset included with each
  // instruction in the original trace port implementation. These have since
  // been removed from TracedInstruction.
  val traceInstSz = (new freechips.rocketchip.rocket.TracedInstruction).getWidth + 2

  // connect the ara core
  val core = Module(new ARACoreBlackbox(
    // traceport params
    traceportEnabled = outer.araParams.trace,
    traceportSz = (outer.araParams.core.retireWidth * traceInstSz),

    // general core params
    hartIdLen = 64, // CONSTANT: The same as AXI address width.
    xLen = p(XLen),
    rasEntries = outer.araParams.core.rasEntries,
    btbEntries = outer.araParams.core.btbEntries,
    bhtEntries = outer.araParams.core.bhtEntries,
    exeRegCnt = executeRegionCnt,
    exeRegBase = executeRegionBases,
    exeRegSz = executeRegionSzs,
    cacheRegCnt = cacheableRegionCnt,
    cacheRegBase = cacheableRegionBases,
    cacheRegSz = cacheableRegionSzs,
    debugBase = debugBaseAddr,
    axiAddrWidth = 64, // CONSTANT: addr width for TL can differ
    axiDataWidth = outer.beatBytes * 8,
    axiUserWidth = outer.sourceBits,
    axiIdWidth = outer.idBits,
    pmpEntries = outer.araParams.core.pmpEntries
  ))

  core.io.clk_i := clock
  core.io.rst_ni := ~reset.asBool
  core.io.boot_addr_i := outer.resetVectorSinkNode.bundle
  core.io.hart_id_i := outer.hartIdSinkNode.bundle

  outer.connectARAInterrupts(core.io.debug_req_i, core.io.ipi_i, core.io.time_irq_i, core.io.irq_i)

  if (outer.araParams.trace) {
    // unpack the trace io from a UInt into Vec(TracedInstructions)
    //outer.traceSourceNode.bundle <> core.io.trace_o.asTypeOf(outer.traceSourceNode.bundle)

    for (w <- 0 until outer.araParams.core.retireWidth) {
      outer.traceSourceNode.bundle.insns(w).valid     := core.io.trace_o(traceInstSz*w + 2)
      outer.traceSourceNode.bundle.insns(w).iaddr     := core.io.trace_o(traceInstSz*w + 42, traceInstSz*w + 3)
      outer.traceSourceNode.bundle.insns(w).insn      := core.io.trace_o(traceInstSz*w + 74, traceInstSz*w + 43)
      outer.traceSourceNode.bundle.insns(w).priv      := core.io.trace_o(traceInstSz*w + 77, traceInstSz*w + 75)
      outer.traceSourceNode.bundle.insns(w).exception := core.io.trace_o(traceInstSz*w + 78)
      outer.traceSourceNode.bundle.insns(w).interrupt := core.io.trace_o(traceInstSz*w + 79)
      outer.traceSourceNode.bundle.insns(w).cause     := core.io.trace_o(traceInstSz*w + 87, traceInstSz*w + 80)
      outer.traceSourceNode.bundle.insns(w).tval      := core.io.trace_o(traceInstSz*w + 127, traceInstSz*w + 88)
    }
  } else {
    outer.traceSourceNode.bundle := DontCare
    outer.traceSourceNode.bundle.insns map (t => t.valid := false.B)
  }

  // connect the axi interface
  outer.memAXI4Node.out foreach { case (out, edgeOut) =>
    core.io.axi_resp_i_aw_ready    := out.aw.ready
    out.aw.valid                   := core.io.axi_req_o_aw_valid
    out.aw.bits.id                 := core.io.axi_req_o_aw_bits_id
    out.aw.bits.addr               := core.io.axi_req_o_aw_bits_addr
    out.aw.bits.len                := core.io.axi_req_o_aw_bits_len
    out.aw.bits.size               := core.io.axi_req_o_aw_bits_size
    out.aw.bits.burst              := core.io.axi_req_o_aw_bits_burst
    out.aw.bits.lock               := core.io.axi_req_o_aw_bits_lock
    out.aw.bits.cache              := core.io.axi_req_o_aw_bits_cache
    out.aw.bits.prot               := core.io.axi_req_o_aw_bits_prot
    out.aw.bits.qos                := core.io.axi_req_o_aw_bits_qos
    // unused signals
    assert(core.io.axi_req_o_aw_bits_region === 0.U)
    assert(core.io.axi_req_o_aw_bits_atop === 0.U)
    assert(core.io.axi_req_o_aw_bits_user === 0.U)

    core.io.axi_resp_i_w_ready     := out.w.ready
    out.w.valid                    := core.io.axi_req_o_w_valid
    out.w.bits.data                := core.io.axi_req_o_w_bits_data
    out.w.bits.strb                := core.io.axi_req_o_w_bits_strb
    out.w.bits.last                := core.io.axi_req_o_w_bits_last
    // unused signals
    assert(core.io.axi_req_o_w_bits_user === 0.U)

    out.b.ready                    := core.io.axi_req_o_b_ready
    core.io.axi_resp_i_b_valid     := out.b.valid
    core.io.axi_resp_i_b_bits_id   := out.b.bits.id
    core.io.axi_resp_i_b_bits_resp := out.b.bits.resp
    core.io.axi_resp_i_b_bits_user := 0.U // unused

    core.io.axi_resp_i_ar_ready    := out.ar.ready
    out.ar.valid                   := core.io.axi_req_o_ar_valid
    out.ar.bits.id                 := core.io.axi_req_o_ar_bits_id
    out.ar.bits.addr               := core.io.axi_req_o_ar_bits_addr
    out.ar.bits.len                := core.io.axi_req_o_ar_bits_len
    out.ar.bits.size               := core.io.axi_req_o_ar_bits_size
    out.ar.bits.burst              := core.io.axi_req_o_ar_bits_burst
    out.ar.bits.lock               := core.io.axi_req_o_ar_bits_lock
    out.ar.bits.cache              := core.io.axi_req_o_ar_bits_cache
    out.ar.bits.prot               := core.io.axi_req_o_ar_bits_prot
    out.ar.bits.qos                := core.io.axi_req_o_ar_bits_qos
    // unused signals
    assert(core.io.axi_req_o_ar_bits_region === 0.U)
    assert(core.io.axi_req_o_ar_bits_user === 0.U)

    out.r.ready                    := core.io.axi_req_o_r_ready
    core.io.axi_resp_i_r_valid     := out.r.valid
    core.io.axi_resp_i_r_bits_id   := out.r.bits.id
    core.io.axi_resp_i_r_bits_data := out.r.bits.data
    core.io.axi_resp_i_r_bits_resp := out.r.bits.resp
    core.io.axi_resp_i_r_bits_last := out.r.bits.last
    core.io.axi_resp_i_r_bits_user := 0.U // unused
  }
}
