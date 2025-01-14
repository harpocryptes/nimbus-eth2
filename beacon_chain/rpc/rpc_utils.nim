# beacon_chain
# Copyright (c) 2018-2021 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [Defect].}

import
  std/[strutils, parseutils],
  stew/byteutils,
  ../beacon_node, ../validators/validator_duties,
  ../consensus_object_pools/[block_pools_types, blockchain_dag],
  ../spec/datatypes/base,
  ../spec/[forks, helpers],
  ../spec/eth2_apis/[rpc_types, eth2_json_rpc_serialization]

export forks, rpc_types, eth2_json_rpc_serialization, blockchain_dag

template raiseNoAltairSupport*() =
  raise (ref ValueError)(msg:
    "The JSON-RPC interface does not support certain Altair operations due to changes in block structure - see https://nimbus.guide/rest-api.html for full altair support")

template withStateForStateId*(stateId: string, body: untyped): untyped =
  let
    bsi = node.stateIdToBlockSlotId(stateId)

  template isState(state: ForkedHashedBeaconState): bool =
    state.matches_block_slot(bsi.bid.root, bsi.slot)

  if isState(node.dag.headState):
    withStateVars(node.dag.headState):
      var cache {.inject, used.}: StateCache
      body
  else:
    let rpcState = assignClone(node.dag.headState)
    node.dag.withUpdatedState(rpcState[], bsi) do:
      body
    do:
      raise (ref CatchableError)(msg: "Trying to access pruned state")

proc parseRoot*(str: string): Eth2Digest {.raises: [Defect, ValueError].} =
  Eth2Digest(data: hexToByteArray[32](str))

func checkEpochToSlotOverflow*(epoch: Epoch) {.raises: [Defect, ValueError].} =
  const maxEpoch = epoch(FAR_FUTURE_SLOT)
  if epoch >= maxEpoch:
    raise newException(
      ValueError, "Requesting epoch for which slot would overflow")

proc doChecksAndGetCurrentHead*(node: BeaconNode, slot: Slot): BlockRef {.raises: [Defect, CatchableError].} =
  result = node.dag.head
  if not node.isSynced(result):
    raise newException(CatchableError, "Cannot fulfill request until node is synced")
  # TODO for now we limit the requests arbitrarily by up to 2 epochs into the future
  if result.slot + uint64(2 * SLOTS_PER_EPOCH) < slot:
    raise newException(CatchableError, "Requesting way ahead of the current head")

proc doChecksAndGetCurrentHead*(node: BeaconNode, epoch: Epoch): BlockRef {.raises: [Defect, CatchableError].} =
  checkEpochToSlotOverflow(epoch)
  node.doChecksAndGetCurrentHead(epoch.start_slot())

proc parseSlot(slot: string): Slot {.raises: [Defect, CatchableError].} =
  if slot.len == 0:
    raise newException(ValueError, "Empty slot number not allowed")
  var parsed: BiggestUInt
  if parseBiggestUInt(slot, parsed) != slot.len:
    raise newException(ValueError, "Not a valid slot number")
  Slot parsed

proc getBlockSlotIdFromString*(node: BeaconNode, slot: string): BlockSlotId {.raises: [Defect, CatchableError].} =
  let parsed = parseSlot(slot)
  discard node.doChecksAndGetCurrentHead(parsed)
  node.dag.getBlockIdAtSlot(parsed).valueOr:
    raise newException(ValueError, "Block not found")

proc getBlockIdFromString*(node: BeaconNode, slot: string): BlockId {.raises: [Defect, CatchableError].} =
  let parsed = parseSlot(slot)
  discard node.doChecksAndGetCurrentHead(parsed)
  let bsid = node.dag.getBlockIdAtSlot(parsed)
  if bsid.isSome and bsid.get.isProposed():
    bsid.get().bid
  else:
    raise (ref ValueError)(msg: "Block not found")

proc stateIdToBlockSlotId*(node: BeaconNode, stateId: string): BlockSlotId {.raises: [Defect, CatchableError].} =
  case stateId:
  of "head":
    node.dag.head.bid.atSlot()
  of "genesis":
    node.dag.genesis.atSlot()
  of "finalized":
    node.dag.finalizedHead.toBlockSlotId().expect("not nil")
  of "justified":
    node.dag.head.atEpochStart(
      getStateField(
        node.dag.headState, current_justified_checkpoint).epoch).
          toBlockSlotId().valueOr:
            raise (ref ValueError)(msg: "State not found")
  else:
    if stateId.startsWith("0x"):
      let stateRoot = parseRoot(stateId)
      if stateRoot == getStateRoot(node.dag.headState):
        node.dag.head.bid.atSlot()
      else:
        # We don't have a state root -> BlockSlot mapping
        raise (ref ValueError)(msg: "State not found")

    else: # Parse as slot number
      node.getBlockSlotIdFromString(stateId)
