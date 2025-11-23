//
//  StatsFooter.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

struct StatsFooter: View {
    let totalDocuments: Int
    let totalChunks: Int
    
    var body: some View {
        HStack(spacing: 16) {
            Label("\(totalDocuments) Documents", systemImage: "doc.on.doc")
            Divider()
                .frame(height: 12)
            Label("\(totalChunks) Chunks", systemImage: "cube.box")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}
