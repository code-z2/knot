import XCTest
@testable import AA
import BigInt
import Passkey
import Transactions
import web3swift

final class AATests: XCTestCase {
  func testInit() {
    _ = AAClient()
  }

  func testLegacyExecuteSingleEncoding() throws {
    let call = Call(to: "0x0000000000000000000000000000000000000001", dataHex: "0x", valueWei: "0")
    let encoded = try SmartAccount.ExecuteSingle.encodeCall(call)

    let expectedSelector = Data("execute(address,uint256,bytes)".utf8).sha3(.keccak256).prefix(4)
    XCTAssertEqual(encoded.prefix(4), expectedSelector)
  }

  func testLegacyExecuteBatchEncoding() throws {
    let callA = Call(to: "0x0000000000000000000000000000000000000001", dataHex: "0x", valueWei: "0")
    let callB = Call(to: "0x0000000000000000000000000000000000000002", dataHex: "0x", valueWei: "0")
    let encoded = try SmartAccount.ExecuteBatch.encodeCall([callA, callB])
    let expectedSelector = Data("executeBatch((address,uint256,bytes)[])".utf8).sha3(.keccak256).prefix(4)
    XCTAssertEqual(encoded.prefix(4), expectedSelector)
  }

  func testExecuteAuthorizedSingleHashVariesByNonceAndDeadline() throws {
    let call = Call(to: "0x0000000000000000000000000000000000000001", dataHex: "0xabcdef", valueWei: "42")
    let account = "0x0000000000000000000000000000000000000abc"
    let chainId: UInt64 = 8453

    let hashA = try SmartAccount.ExecuteAuthorized.hashSingle(
      account: account,
      chainId: chainId,
      call: call,
      nonce: 1,
      deadline: 100
    )
    let hashB = try SmartAccount.ExecuteAuthorized.hashSingle(
      account: account,
      chainId: chainId,
      call: call,
      nonce: 2,
      deadline: 100
    )
    let hashC = try SmartAccount.ExecuteAuthorized.hashSingle(
      account: account,
      chainId: chainId,
      call: call,
      nonce: 1,
      deadline: 101
    )

    XCTAssertEqual(hashA.count, 32)
    XCTAssertNotEqual(hashA, hashB)
    XCTAssertNotEqual(hashA, hashC)
  }

  func testExecuteAuthorizedBatchHashVariesByChainAndAccount() throws {
    let calls = [
      Call(to: "0x0000000000000000000000000000000000000001", dataHex: "0x", valueWei: "1"),
      Call(to: "0x0000000000000000000000000000000000000002", dataHex: "0x01", valueWei: "2"),
    ]

    let hashA = try SmartAccount.ExecuteAuthorized.hashBatch(
      account: "0x00000000000000000000000000000000000000aa",
      chainId: 8453,
      calls: calls,
      nonce: 7,
      deadline: 999
    )
    let hashB = try SmartAccount.ExecuteAuthorized.hashBatch(
      account: "0x00000000000000000000000000000000000000bb",
      chainId: 8453,
      calls: calls,
      nonce: 7,
      deadline: 999
    )
    let hashC = try SmartAccount.ExecuteAuthorized.hashBatch(
      account: "0x00000000000000000000000000000000000000aa",
      chainId: 10,
      calls: calls,
      nonce: 7,
      deadline: 999
    )

    XCTAssertEqual(hashA.count, 32)
    XCTAssertNotEqual(hashA, hashB)
    XCTAssertNotEqual(hashA, hashC)
  }

  func testExecuteAuthorizedSingleEncodingLayout() throws {
    let call = Call(
      to: "0x0000000000000000000000000000000000000011",
      dataHex: "0xabcdef",
      valueWei: "55"
    )
    let nonce: UInt64 = 9
    let deadline: UInt64 = 123456
    let signature = Data(repeating: 0x42, count: 65)

    let encoded = try SmartAccount.ExecuteAuthorized.encodeSingle(
      call: call,
      nonce: nonce,
      deadline: deadline,
      signature: signature
    )

    let selector = Data("execute((address,uint256,bytes),uint256,uint256,bytes)".utf8).sha3(.keccak256).prefix(4)
    XCTAssertEqual(encoded.prefix(4), selector)
    XCTAssertEqual(word(encoded, 1), ABIWord.uint(BigUInt(nonce)))
    XCTAssertEqual(word(encoded, 2), ABIWord.uint(BigUInt(deadline)))
  }

  func testExecuteAuthorizedBatchEncodingLayout() throws {
    let calls = [Call(to: "0x0000000000000000000000000000000000000011", dataHex: "0x", valueWei: "0")]
    let nonce: UInt64 = 77
    let deadline: UInt64 = 500
    let signature = Data(repeating: 0xaa, count: 65)

    let encoded = try SmartAccount.ExecuteAuthorized.encodeBatch(
      calls: calls,
      nonce: nonce,
      deadline: deadline,
      signature: signature
    )

    let selector = Data("executeBatch((address,uint256,bytes)[],uint256,uint256,bytes)".utf8).sha3(.keccak256).prefix(4)
    XCTAssertEqual(encoded.prefix(4), selector)
    XCTAssertEqual(word(encoded, 1), ABIWord.uint(BigUInt(nonce)))
    XCTAssertEqual(word(encoded, 2), ABIWord.uint(BigUInt(deadline)))
  }

  func testInitializeSignatureDigestMatchesContractLayout() throws {
    let passkey = PasskeyPublicKey(
      x: Data(repeating: 0x11, count: 32),
      y: Data(repeating: 0x22, count: 32),
      credentialID: Data([0x01])
    )
    let config = InitializationConfig(
      accumulatorFactory: "0x00000000000000000000000000000000000000f1",
      wrappedNativeToken: "0x00000000000000000000000000000000000000f2",
      spokePool: "0x00000000000000000000000000000000000000f3"
    )
    let account = "0x0000000000000000000000000000000000000abc"
    let chainId: UInt64 = 8453

    let digest = try SmartAccount.Initialize.initSignatureDigest(
      account: account,
      chainId: chainId,
      passkeyPublicKey: passkey,
      config: config
    )

    let expected = Data(
      (
        ABIWord.uint(BigUInt(chainId))
          + (try ABIWord.address(account))
          + (try ABIWord.bytes32(passkey.x))
          + (try ABIWord.bytes32(passkey.y))
          + (try ABIWord.address(config.accumulatorFactory))
          + (try ABIWord.address(config.wrappedNativeToken))
          + (try ABIWord.address(config.spokePool))
      ).sha3(.keccak256)
    )
    XCTAssertEqual(digest, expected)
  }

  func testInitializeEncodingLayout() throws {
    let passkey = PasskeyPublicKey(
      x: Data(repeating: 0x01, count: 32),
      y: Data(repeating: 0x02, count: 32),
      credentialID: Data([0xaa])
    )
    let config = InitializationConfig(
      accumulatorFactory: "0x00000000000000000000000000000000000000f1",
      wrappedNativeToken: "0x00000000000000000000000000000000000000f2",
      spokePool: "0x00000000000000000000000000000000000000f3"
    )
    let initSignature = Data(repeating: 0xab, count: 65)

    let encoded = try SmartAccount.Initialize.encodeCall(
      passkeyPublicKey: passkey,
      config: config,
      initSignature: initSignature
    )

    let selector = Data("initialize(bytes32,bytes32,address,address,address,bytes)".utf8).sha3(.keccak256).prefix(4)
    XCTAssertEqual(encoded.prefix(4), selector)
    XCTAssertEqual(word(encoded, 0), passkey.x)
    XCTAssertEqual(word(encoded, 1), passkey.y)
    XCTAssertEqual(word(encoded, 2), try ABIWord.address(config.accumulatorFactory))
    XCTAssertEqual(word(encoded, 3), try ABIWord.address(config.wrappedNativeToken))
    XCTAssertEqual(word(encoded, 4), try ABIWord.address(config.spokePool))
  }

  func testCrossChainOrderEncodingHasExpectedSelectorAndOffsets() throws {
    let order = OnchainCrossChainOrder(
      orderDataType: Data(repeating: 0x44, count: 32),
      fillDeadline: 123,
      orderData: Data([0xde, 0xad, 0xbe, 0xef])
    )
    let signature = Data(repeating: 0x99, count: 65)

    let encoded = try SmartAccount.CrossChainOrder.encodeCall(order: order, signature: signature)

    let selector = Data("executeCrossChainOrder((bytes32,uint32,bytes),bytes)".utf8).sha3(.keccak256).prefix(4)
    XCTAssertEqual(encoded.prefix(4), selector)
    XCTAssertEqual(word(encoded, 0), ABIWord.uint(BigUInt(64)))
    XCTAssertGreaterThan(encoded.count, 4 + 64)
  }

  func testAuxiliaryEncodersHaveExpectedSelectors() throws {
    let accumulatorCall = try SmartAccount.AccumulatorFactory.encodeComputeAddressCall(
      userAccount: "0x0000000000000000000000000000000000000001"
    )
    let accumulatorSelector = Data("computeAddress(address)".utf8).sha3(.keccak256).prefix(4)
    XCTAssertEqual(accumulatorCall.prefix(4), accumulatorSelector)

    let sigCall = try SmartAccount.IsValidSignature.encodeCall(
      hash: Data(repeating: 0x77, count: 32),
      signature: Data(repeating: 0x88, count: 65)
    )
    let sigSelector = Data("isValidSignature(bytes32,bytes)".utf8).sha3(.keccak256).prefix(4)
    XCTAssertEqual(sigCall.prefix(4), sigSelector)
  }

  private func word(_ data: Data, _ index: Int) -> Data {
    let start = 4 + (index * 32)
    return data.subdata(in: start..<(start + 32))
  }
}
