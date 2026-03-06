//
//  ProcessingOverlay.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

struct ProcessingOverlay: View {
    let status: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text(status)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Material.ultraThinMaterial)
            )
            .shadow(radius: 20)
        }
    }
}

#Preview {
    ProcessingOverlay(status: "Processing document...")
}
