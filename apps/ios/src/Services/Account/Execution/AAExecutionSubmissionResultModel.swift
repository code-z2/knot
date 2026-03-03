// AAExecutionSubmissionResultModel.swift
// Created by Peter Anyaogu on 02/03/2026.

import RPC

struct AAExecutionSubmissionResultModel: Sendable {
    let destinationSubmission: RelaySubmissionModel
    let immediateSubmissions: [RelaySubmissionModel]
    let backgroundSubmissions: [RelaySubmissionModel]
    let deferredSubmissions: [RelaySubmissionModel]
}
