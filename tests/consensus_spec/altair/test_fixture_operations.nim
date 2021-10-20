# beacon_chain
# Copyright (c) 2018-2021 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.used.}

import
  # Standard library
  std/[os, sequtils, sets],
  # Utilities
  chronicles,
  unittest2,
  stew/results,
  # Beacon chain internals
  ../../../beacon_chain/spec/[beaconstate, state_transition_block],
  ../../../beacon_chain/spec/datatypes/altair,
  # Test utilities
  ../../testutil,
  ../fixtures_utils,
  ../../helpers/debug_state

const
  OpDir                 = SszTestsDir/const_preset/"altair"/"operations"
  OpAttestationsDir     = OpDir/"attestation"
  OpAttSlashingDir      = OpDir/"attester_slashing"
  OpBlockHeaderDir      = OpDir/"block_header"
  OpDepositsDir         = OpDir/"deposit"
  OpProposerSlashingDir = OpDir/"proposer_slashing"
  OpSyncAggregateDir    = OpDir/"sync_aggregate"
  OpVoluntaryExitDir    = OpDir/"voluntary_exit"

  baseDescription = "Ethereum Foundation - Altair - Operations - "

doAssert toHashSet(mapIt(toSeq(walkDir(OpDir, relative = false)), it.path)) ==
  toHashSet([OpAttestationsDir, OpAttSlashingDir, OpBlockHeaderDir,
             OpDepositsDir, OpProposerSlashingDir, OpSyncAggregateDir,
             OpVoluntaryExitDir])

proc runTest[T, U](
    testSuiteDir: string, testSuiteName: string, applyFile: string,
    applyProc: U, identifier: string) =
  let testDir = testSuiteDir / "pyspec_tests" / identifier

  proc testImpl() =
    let prefix =
      if existsFile(testDir/"post.ssz_snappy"):
        "[Valid]   "
      else:
        "[Invalid] "

    test prefix & baseDescription & testSuiteName & " - " & identifier:
      var preState = newClone(
        parseTest(testDir/"pre.ssz_snappy", SSZ, altair.BeaconState))
      let done = applyProc(
        preState[], parseTest(testDir/(applyFile & ".ssz_snappy"), SSZ, T))

      if existsFile(testDir/"post.ssz_snappy"):
        let postState =
          newClone(parseTest(testDir/"post.ssz_snappy", SSZ, altair.BeaconState))

        check:
          done.isOk()
          preState[].hash_tree_root() == postState[].hash_tree_root()
        reportDiff(preState, postState)
      else:
        check: done.isErr() # No post state = processing should fail

  testImpl()

suite baseDescription & "Attestation " & preset():
  proc applyAttestation(
      preState: var altair.BeaconState, attestation: Attestation):
      Result[void, cstring] =
    var cache = StateCache()
    let
      total_active_balance = get_total_active_balance(preState, cache)
      base_reward_per_increment =
        get_base_reward_per_increment(total_active_balance)

    process_attestation(
      preState, attestation, {}, base_reward_per_increment, cache)

  for path in walkTests(OpAttestationsDir):
    runTest[Attestation, typeof applyAttestation](
      OpAttestationsDir, "Attestation", "attestation", applyAttestation, path)

suite baseDescription & "Attester Slashing " & preset():
  proc applyAttesterSlashing(
      preState: var altair.BeaconState, attesterSlashing: AttesterSlashing):
      Result[void, cstring] =
    var cache = StateCache()
    process_attester_slashing(
      defaultRuntimeConfig, preState, attesterSlashing, {}, cache)

  for path in walkTests(OpAttSlashingDir):
    runTest[AttesterSlashing, typeof applyAttesterSlashing](
      OpAttSlashingDir, "Attester Slashing", "attester_slashing",
      applyAttesterSlashing, path)

suite baseDescription & "Block Header " & preset():
  func applyBlockHeader(
      preState: var altair.BeaconState, blck: altair.BeaconBlock):
      Result[void, cstring] =
    var cache = StateCache()
    process_block_header(preState, blck, {}, cache)

  for path in walkTests(OpBlockHeaderDir):
    runTest[altair.BeaconBlock, typeof applyBlockHeader](
      OpBlockHeaderDir, "Block Header", "block", applyBlockHeader, path)

suite baseDescription & "Deposit " & preset():
  proc applyDeposit(
      preState: var altair.BeaconState, deposit: Deposit):
      Result[void, cstring] =
    process_deposit(defaultRuntimeConfig, preState, deposit, {})

  for path in walkTests(OpDepositsDir):
    runTest[Deposit, typeof applyDeposit](
      OpDepositsDir, "Deposit", "deposit", applyDeposit, path)

suite baseDescription & "Proposer Slashing " & preset():
  proc applyProposerSlashing(
      preState: var altair.BeaconState, proposerSlashing: ProposerSlashing):
      Result[void, cstring] =
    var cache = StateCache()
    process_proposer_slashing(
      defaultRuntimeConfig, preState, proposerSlashing, {}, cache)

  for path in walkTests(OpProposerSlashingDir):
    runTest[ProposerSlashing, typeof applyProposerSlashing](
      OpProposerSlashingDir, "Proposer Slashing", "proposer_slashing",
      applyProposerSlashing, path)

suite baseDescription & "Sync Aggregate " & preset():
  proc applySyncAggregate(
      preState: var altair.BeaconState, syncAggregate: SyncAggregate):
      Result[void, cstring] =
    var cache = StateCache()
    process_sync_aggregate(
      preState, syncAggregate, get_total_active_balance(preState, cache), cache)

  for path in walkTests(OpSyncAggregateDir):
    runTest[SyncAggregate, typeof applySyncAggregate](
      OpSyncAggregateDir, "Sync Aggregate", "sync_aggregate",
      applySyncAggregate, path)

suite baseDescription & "Voluntary Exit " & preset():
  proc applyVoluntaryExit(
      preState: var altair.BeaconState, voluntaryExit: SignedVoluntaryExit):
      Result[void, cstring] =
    var cache = StateCache()
    process_voluntary_exit(
      defaultRuntimeConfig, preState, voluntaryExit, {}, cache)

  for path in walkTests(OpVoluntaryExitDir):
    runTest[SignedVoluntaryExit, typeof applyVoluntaryExit](
      OpVoluntaryExitDir, "Voluntary Exit", "voluntary_exit",
      applyVoluntaryExit, path)
