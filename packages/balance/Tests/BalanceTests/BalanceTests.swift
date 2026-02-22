@testable import Balance
import Foundation
import RPC
import XCTest

final class BalanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.handler = nil
    }

    func testFetchBalancesGroupsWrappedAndNativeSymbols() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic dGVzdC1rZXk6")
            let absolute = request.url?.absoluteString ?? ""
            XCTAssertTrue(absolute.contains("filter%5Bchain_ids%5D="))
            XCTAssertTrue(absolute.contains("filter%5Btrash%5D=only_non_trash"))
            XCTAssertTrue(absolute.contains("ethereum"))
            XCTAssertTrue(absolute.contains("base"))

            let payload = """
            {
              "data": [
                {
                  "id": "eth-position",
                  "attributes": {
                    "quantity": { "numeric": "1.25", "decimals": 18 },
                    "value": 3250,
                    "price": 2600,
                    "changes": { "percent_1d": 10 },
                    "fungible_info": {
                      "name": "Ethereum",
                      "symbol": "ETH",
                      "icon": { "url": "https://cdn.zerion.io/eth.png" },
                      "implementations": [
                        { "chain_id": "ethereum", "address": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" }
                      ]
                    }
                  },
                  "relationships": {
                    "chain": { "data": { "type": "chains", "id": "ethereum" } }
                  }
                },
                {
                  "id": "weth-position",
                  "attributes": {
                    "quantity": { "numeric": "2.75", "decimals": 18 },
                    "value": 7150,
                    "price": 2600,
                    "fungible_info": {
                      "name": "Wrapped Ether",
                      "symbol": "WETH",
                      "icon": { "url": "https://cdn.zerion.io/weth.png" },
                      "implementations": [
                        { "chain_id": "base", "address": "0x4200000000000000000000000000000000000006" }
                      ]
                    }
                  },
                  "relationships": {
                    "chain": { "data": { "type": "chains", "id": "base" } }
                  }
                }
              ],
              "links": { "next": null }
            }
            """

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil,
            )!
            return (response, Data(payload.utf8))
        }

        let provider = ZerionBalanceProvider(session: makeStubSession())
        let balances = try await provider.fetchBalances(
            walletAddress: "0xabc",
            positionsAPIURL: "https://api.zerion.io/v1/wallets/{walletAddress}/positions/",
            apiKey: "test-key",
            supportedChainIDs: [1, 8453],
            includeTestnets: false,
            zerionChainMapping: mapping(chainIDs: [1, 8453]),
        )

        XCTAssertEqual(balances.count, 1)
        XCTAssertEqual(balances[0].symbol, "ETH")
        XCTAssertEqual(balances[0].chainBalances.count, 2)
        XCTAssertEqual(decimalString(balances[0].totalBalance), "4")
        XCTAssertEqual(decimalString(balances[0].totalValueUSD), "10400")
        let changeRatio = NSDecimalNumber(decimal: balances[0].priceChangeRatio24h ?? 0).doubleValue
        XCTAssertEqual(changeRatio, 0.10, accuracy: 0.000001)
    }

    func testFetchBalancesFiltersUnsupportedChains() async throws {
        URLProtocolStub.handler = { request in
            let payload = """
            {
              "data": [
                {
                  "id": "eth-position",
                  "attributes": {
                    "quantity": { "numeric": "1", "decimals": 18 },
                    "value": 1000,
                    "price": 1000,
                    "fungible_info": {
                      "name": "Ethereum",
                      "symbol": "ETH",
                      "implementations": [
                        { "chain_id": "ethereum", "address": "0xeeee" }
                      ]
                    }
                  },
                  "relationships": {
                    "chain": { "data": { "type": "chains", "id": "ethereum" } }
                  }
                },
                {
                  "id": "sepolia-position",
                  "attributes": {
                    "quantity": { "numeric": "3", "decimals": 18 },
                    "value": 3000,
                    "price": 1000,
                    "fungible_info": {
                      "name": "Ethereum",
                      "symbol": "ETH",
                      "implementations": [
                        { "chain_id": "sepolia", "address": "0xsepo" }
                      ]
                    }
                  },
                  "relationships": {
                    "chain": { "data": { "type": "chains", "id": "sepolia" } }
                  }
                }
              ],
              "links": { "next": null }
            }
            """

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil,
            )!
            return (response, Data(payload.utf8))
        }

        let provider = ZerionBalanceProvider(session: makeStubSession())
        let balances = try await provider.fetchBalances(
            walletAddress: "0xabc",
            positionsAPIURL: "https://api.zerion.io/v1/wallets/{walletAddress}/positions/",
            apiKey: "test-key",
            supportedChainIDs: [1],
            includeTestnets: false,
            zerionChainMapping: mapping(chainIDs: [1]),
        )

        XCTAssertEqual(balances.count, 1)
        XCTAssertEqual(decimalString(balances[0].totalBalance), "1")
        XCTAssertEqual(balances[0].chainBalances.map(\.chainID), [1])
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func mapping(chainIDs: Set<UInt64>) -> ZerionChainMappingModel {
        let baseMapping: [UInt64: String] = [
            1: "ethereum",
            8453: "base",
            11_155_111: "sepolia",
            84532: "base_sepolia",
            42161: "arbitrum",
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

        return ZerionChainMappingModel(
            zerionIDByChainID: zerionIDByChainID,
            chainIDByZerionID: chainIDByZerionID,
        )
    }
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with _: URLRequest) -> Bool {
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
