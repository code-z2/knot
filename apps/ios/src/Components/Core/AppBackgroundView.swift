// AppBackgroundView.swift
// Created by Peter Anyaogu

import SwiftUI

struct AppBackgroundView: View {
    var body: some View {
        ZStack(alignment: .top) {
            AppThemeColor.backgroundPrimary
                .ignoresSafeArea()

            ZStack {
                // Outer subtle glow
                Ellipse()
                    .fill(AppThemeColor.accentBrown.opacity(0.12))
                    .frame(width: 278, height: 278)
                    .blur(radius: 100)

                // Inner focused glow
                Ellipse()
                    .fill(AppThemeColor.accentBrown.opacity(0.18))
                    .frame(width: 167, height: 167)
                    .blur(radius: 100)
            }
            .ignoresSafeArea()
        }
    }
}

#Preview {
    AppBackgroundView()
        .preferredColorScheme(.dark)
}
