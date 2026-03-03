// StoredSingletonConfig.swift
// Created by Peter Anyaogu on 02/03/2026.

import Foundation

struct StoredSingletonConfig: Codable, Sendable, Equatable {
    let delegateAddress: String
    let accumulatorFactory: String
    let version: String

    init(delegateAddress: String, accumulatorFactory: String, version: String) {
        self.delegateAddress = delegateAddress.lowercased()
        self.accumulatorFactory = accumulatorFactory.lowercased()
        self.version = version
    }
}
