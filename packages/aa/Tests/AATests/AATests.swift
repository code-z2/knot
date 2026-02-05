import XCTest
@testable import AA
import BigInt
import Transactions

final class AATests: XCTestCase {
  func testInit() {
    _ = AAClient()
  }

  func testExecuteRouterUsesSingleForOneCall() throws {
    let call = Call(to: "0x0000000000000000000000000000000000000001", dataHex: "0x", valueWei: "0")
    let single = try SmartAccount.ExecuteSingle.encodeCall(call)
    let routed = try SmartAccount.Execute.encodeCall([call])
    XCTAssertEqual(routed, single)
  }

  func testExecuteRouterUsesBatchForMultipleCalls() throws {
    let callA = Call(to: "0x0000000000000000000000000000000000000001", dataHex: "0x", valueWei: "0")
    let callB = Call(to: "0x0000000000000000000000000000000000000002", dataHex: "0x", valueWei: "0")
    let batch = try SmartAccount.ExecuteBatch.encodeCall([callA, callB])
    let routed = try SmartAccount.Execute.encodeCall([callA, callB])
    XCTAssertEqual(routed, batch)
  }

  func testUserOperationPackAndHash() throws {
    let userOperation = UserOperation(
      chainId: 8453,
      sender: "0x5a6b47f4131bf1feafa56a05573314bcf44c9149",
      nonce: "0x1",
      callData: "0xabcd",
      maxPriorityFeePerGas: "0x3b9aca00",
      maxFeePerGas: "0x7a5cf70d5",
      callGasLimit: "0x13880",
      verificationGasLimit: "0x60b01",
      preVerificationGas: "0xd3e3",
      paymaster: "0x",
      signature: "0x",
      eip7702Auth: EIP7702Auth(
        address: "0x1111111111111111111111111111111111111111",
        chainId: "0x2105",
        nonce: "0x0",
        r: "0x1",
        s: "0x2",
        yParity: "0x1"
      )
    )

    let packed = try userOperation.packForSignature()
    XCTAssertEqual(packed.sender, userOperation.sender)
    XCTAssertTrue(packed.initCodeHash.hasPrefix("0x"))
    XCTAssertTrue(packed.callDataHash.hasPrefix("0x"))
    XCTAssertEqual(packed.accountGasLimits.count, 66)
    XCTAssertEqual(packed.gasFees.count, 66)
    let hash = try userOperation.hash()
    XCTAssertEqual(hash.count, 32)
  }

  func testUserOperationUpdateSignature() {
    let userOperation = UserOperation(
      chainId: 8453,
      sender: "0x5a6b47f4131bf1feafa56a05573314bcf44c9149",
      nonce: "0x1",
      callData: "0xabcd",
      maxPriorityFeePerGas: "0x1",
      maxFeePerGas: "0x1",
      callGasLimit: "0x1",
      verificationGasLimit: "0x1",
      preVerificationGas: "0x1"
    )
    let updated = userOperation.update(signature: Data([0xaa, 0xbb]))
    XCTAssertEqual(updated.signature, "0xaabb")
  }

  func testCompactOperationsUsesHighestSelectedFields() throws {
    let auth = EIP7702Auth(
      address: "0x1111111111111111111111111111111111111111",
      chainId: "0x2105",
      nonce: "0x0",
      r: "0x1",
      s: "0x2",
      yParity: "0x1"
    )
    let opA = UserOperation(
      chainId: 8453,
      sender: "0x5a6b47f4131bf1feafa56a05573314bcf44c9149",
      nonce: "0x1",
      callData: "0xabcd",
      maxPriorityFeePerGas: "0x10",
      maxFeePerGas: "0x50",
      callGasLimit: "0x1000",
      verificationGasLimit: "0x2000",
      preVerificationGas: "0x3000",
      paymaster: "0x2222222222222222222222222222222222222222",
      paymasterData: "0xaaaa",
      eip7702Auth: auth
    )
    let opB = UserOperation(
      chainId: 84532,
      sender: "0x5a6b47f4131bf1feafa56a05573314bcf44c9149",
      nonce: "0x2",
      callData: "0xef",
      maxPriorityFeePerGas: "0x20",
      maxFeePerGas: "0x40",
      callGasLimit: "0x4000",
      verificationGasLimit: "0x1000",
      preVerificationGas: "0x1234",
      paymaster: "0x3333333333333333333333333333333333333333",
      paymasterData: "0xbbbb",
      eip7702Auth: auth
    )

    let compacted = try AACompactionTemp.compactOperations([opA, opB])
    XCTAssertEqual(compacted.count, 2)
    XCTAssertEqual(compacted[0].maxFeePerGas, "0x50")
    XCTAssertEqual(compacted[0].maxPriorityFeePerGas, "0x20")
    XCTAssertEqual(compacted[0].verificationGasLimit, "0x2000")
    XCTAssertEqual(compacted[0].callGasLimit, "0x4000")
    XCTAssertEqual(compacted[0].preVerificationGas, "0x3000")
    XCTAssertEqual(compacted[0].paymaster, "0x2222222222222222222222222222222222222222")
    XCTAssertEqual(compacted[0].paymasterData, "0xaaaa")
  }

  func testCompactOperationsPrependsChainCallsSelector() throws {
    let chainCalls = [ChainCalls(chainId: 8453, calls: [])]
    let callData = try SmartAccount.ExecuteChainCalls.encodeCall(chainCalls: chainCalls)
    let op = UserOperation(
      chainId: 8453,
      sender: "0x5a6b47f4131bf1feafa56a05573314bcf44c9149",
      nonce: "0x1",
      callData: "0x" + callData.toHexString(),
      maxPriorityFeePerGas: "0x1",
      maxFeePerGas: "0x1",
      callGasLimit: "0x1",
      verificationGasLimit: "0x1",
      preVerificationGas: "0x1",
      eip7702Auth: EIP7702Auth(
        address: "0x1111111111111111111111111111111111111111",
        chainId: "0x2105",
        nonce: "0x0",
        r: "0x1",
        s: "0x2",
        yParity: "0x1"
      )
    )

    let compacted = try AACompactionTemp.compactOperations([op])
    let compactedData = try AAUtils.hexToData(compacted[0].callData)
    let selector = Data("executeChainCalls(bytes)".utf8).sha3(.keccak256).prefix(4)
    let bytesOffset = Int(BigUInt(compactedData.subdata(in: 4..<(4 + 32))))
    let payloadLengthIndex = 4 + bytesOffset
    let payloadStart = payloadLengthIndex + 32
    let payload = compactedData.subdata(in: payloadStart..<(payloadStart + 4))
    XCTAssertEqual(payload.prefix(4), selector)
  }
}
