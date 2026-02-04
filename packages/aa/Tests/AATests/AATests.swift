import XCTest
@testable import AA
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
}
