//
//  TransactionConfirmationDetailModel.swift
//  Created by Martin Lasek on 24/02/2026.
//

import SwiftUI

struct TransactionConfirmationDetailModel: Identifiable {
    let id = UUID()

    let label: LocalizedStringKey

    let value: TransactionConfirmationDetailValue
}
