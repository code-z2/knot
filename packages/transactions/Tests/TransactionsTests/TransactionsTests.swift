import Foundation
import RPC
import XCTest
@testable import Transactions

final class TransactionsTests: XCTestCase {
  override func setUp() {
    super.setUp()
    URLProtocolStub.handler = nil
  }

  func testFetchTransactionsClassifiesSentAndReceived() async throws {
    URLProtocolStub.handler = { request in
      let absolute = request.url?.absoluteString ?? ""
      XCTAssertTrue(absolute.contains("filter%5Btrash%5D=only_non_trash"))

      let payload = """
      {
        "data": [
          {
            "id": "sent-tx",
            "attributes": {
              "operation_type": "send",
              "hash": "0x01",
              "mined_at_block": 123,
              "mined_at": "2026-02-01T10:00:00Z",
              "sent_from": "0xabc",
              "sent_to": "0xdef",
              "status": "confirmed",
              "nonce": 1,
              "fee": {
                "value": "0.5",
                "fungible_info": { "symbol": "ETH", "name": "Ethereum", "icon": { "url": "https://cdn.zerion.io/eth.png" } }
              },
              "transfers": [
                {
                  "direction": "out",
                  "quantity": { "numeric": "10" },
                  "value": "100",
                  "fungible_info": { "symbol": "USDC", "name": "USDC", "icon": { "url": "https://cdn.zerion.io/usdc.png" } }
                }
              ]
            },
            "relationships": {
              "chain": { "data": { "type": "chains", "id": "base" } }
            }
          },
          {
            "id": "receive-tx",
            "attributes": {
              "operation_type": "receive",
              "hash": "0x02",
              "mined_at_block": 124,
              "mined_at": "2026-02-01T09:00:00Z",
              "sent_from": "0xdef",
              "sent_to": "0xabc",
              "status": "confirmed",
              "nonce": 2,
              "fee": {
                "value": "0.1",
                "fungible_info": { "symbol": "ETH", "name": "Ethereum", "icon": { "url": "https://cdn.zerion.io/eth.png" } }
              },
              "transfers": [
                {
                  "direction": "in",
                  "quantity": { "numeric": "2.5" },
                  "value": "25",
                  "fungible_info": { "symbol": "USDC", "name": "USDC", "icon": { "url": "https://cdn.zerion.io/usdc.png" } }
                }
              ]
            },
            "relationships": {
              "chain": { "data": { "type": "chains", "id": "base" } }
            }
          }
        ],
        "links": {
          "next": "https://api.zerion.io/v1/wallets/0xabc/transactions/?page%5Bafter%5D=cursor-1"
        }
      }
      """

      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, Data(payload.utf8))
    }

    let provider = ZerionTransactionProvider(session: makeStubSession())
    let page = try await provider.fetchTransactions(
      walletAddress: "0xabc",
      accumulatorAddress: nil,
      transactionsAPIURL: "https://api.zerion.io/v1/wallets/{walletAddress}/transactions/",
      apiKey: "test-key",
      supportedChainIDs: [8_453],
      includeTestnets: false,
      cursorAfter: nil,
      zerionChainMapping: mapping(chainIDs: [8_453])
    )

    XCTAssertEqual(page.hasMore, true)
    XCTAssertEqual(page.cursorAfter, "cursor-1")
    XCTAssertEqual(page.sections.count, 1)
    XCTAssertEqual(page.sections[0].transactions.count, 2)

    let byHash = Dictionary(uniqueKeysWithValues: page.sections[0].transactions.map { ($0.txHash, $0) })
    XCTAssertEqual(byHash["0x01"]?.variant, .sent)
    XCTAssertEqual(byHash["0x02"]?.variant, .received)
  }

  func testFetchTransactionsMarksAccumulatorSendAsMultichain() async throws {
    URLProtocolStub.handler = { request in
      let path = request.url?.path ?? ""
      let payload: String

      if path.contains("/wallets/0xacc/") {
        payload = """
        {
          "data": [
            {
              "id": "acc-tx",
              "attributes": {
                "operation_type": "send",
                "hash": "0xacc01",
                "mined_at_block": 200,
                "mined_at": "2026-02-02T10:00:00Z",
                "sent_from": "0xacc",
                "sent_to": "0xrecipient",
                "status": "confirmed",
                "nonce": 3,
                "fee": { "value": "0.2" },
                "transfers": [
                  {
                    "direction": "out",
                    "quantity": { "numeric": "4" },
                    "value": "40",
                    "fungible_info": { "symbol": "USDC", "name": "USDC", "icon": { "url": "https://cdn.zerion.io/usdc.png" } }
                  }
                ]
              },
              "relationships": {
                "chain": { "data": { "type": "chains", "id": "base" } }
              }
            }
          ],
          "links": { "next": null }
        }
        """
      } else {
        payload = """
        {
          "data": [],
          "links": { "next": null }
        }
        """
      }

      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, Data(payload.utf8))
    }

    let provider = ZerionTransactionProvider(session: makeStubSession())
    let page = try await provider.fetchTransactions(
      walletAddress: "0xabc",
      accumulatorAddress: "0xacc",
      transactionsAPIURL: "https://api.zerion.io/v1/wallets/{walletAddress}/transactions/",
      apiKey: "test-key",
      supportedChainIDs: [8_453],
      includeTestnets: false,
      cursorAfter: nil,
      zerionChainMapping: mapping(chainIDs: [8_453])
    )

    XCTAssertEqual(page.sections.count, 1)
    XCTAssertEqual(page.sections[0].transactions.count, 1)
    XCTAssertEqual(page.sections[0].transactions[0].variant, .multichain)
    XCTAssertEqual(page.sections[0].transactions[0].multichainRecipient, "0xrecipient")
  }

  func testFetchTransactionsCanIncludeTrashWhenRequested() async throws {
    URLProtocolStub.handler = { request in
      let absolute = request.url?.absoluteString ?? ""
      XCTAssertTrue(absolute.contains("filter%5Btrash%5D=no_filter"))

      let payload = """
      {
        "data": [],
        "links": { "next": null }
      }
      """

      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, Data(payload.utf8))
    }

    let provider = ZerionTransactionProvider(session: makeStubSession())
    _ = try await provider.fetchTransactions(
      walletAddress: "0xabc",
      accumulatorAddress: nil,
      transactionsAPIURL: "https://api.zerion.io/v1/wallets/{walletAddress}/transactions/",
      apiKey: "test-key",
      supportedChainIDs: [8_453],
      includeTestnets: false,
      cursorAfter: nil,
      includeTrash: true,
      zerionChainMapping: mapping(chainIDs: [8_453])
    )
  }

  private func makeStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
  }

  private func mapping(chainIDs: Set<UInt64>) -> ZerionChainMapping {
    let baseMapping: [UInt64: String] = [
      1: "ethereum",
      8_453: "base",
      11_155_111: "sepolia",
      84_532: "base_sepolia",
      42_161: "arbitrum",
      421_614: "arbitrum_sepolia",
      10: "optimism",
      137: "polygon",
    ]

    var zerionIDByChainID: [UInt64: String] = [:]
    var chainIDByZerionID: [String: UInt64] = [:]
    for chainID in chainIDs {
      guard let zerionID = baseMapping[chainID] else { continue }
      zerionIDByChainID[chainID] = zerionID
      chainIDByZerionID[zerionID] = chainID
    }

    return ZerionChainMapping(
      zerionIDByChainID: zerionIDByChainID,
      chainIDByZerionID: chainIDByZerionID
    )
  }
}

private final class URLProtocolStub: URLProtocol {
  static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
