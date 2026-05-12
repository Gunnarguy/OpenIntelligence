//
//  DocumentRow.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

struct DocumentRow: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: iconName(for: document.contentType))
                    .foregroundColor(.accentColor)
                Text(document.filename)
                    .font(.headline)
            }

            HStack {
                Text("\(document.totalChunks) chunks")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(document.addedAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func iconName(for type: DocumentType) -> String {
        DocumentRow.iconName(for: type)
    }
}

extension DocumentRow {
    static func iconName(for type: DocumentType) -> String {
        switch type {
        // Documents
        case .pdf:
            return "doc.fill"
        case .text:
            return "doc.text.fill"
        case .markdown:
            return "doc.richtext.fill"
        case .rtf:
            return "doc.richtext.fill"

        // Images
        case .png, .jpeg, .heic, .tiff, .gif, .image:
            return "photo.fill"

        // Code files
        case .swift:
            return "swift"
        case .python:
            return "chevron.left.forwardslash.chevron.right"
        case .javascript, .typescript:
            return "curlybraces"
        case .java, .cpp, .c, .objc, .go, .rust, .ruby, .php:
            return "chevron.left.forwardslash.chevron.right"
        case .html, .css, .xml:
            return "chevron.left.forwardslash.chevron.right"
        case .json, .yaml:
            return "curlybraces.square.fill"
        case .sql:
            return "cylinder.fill"
        case .shell, .code:
            return "terminal.fill"

        // Office documents
        case .word:
            return "doc.text.fill"
        case .excel, .csv:
            return "tablecells.fill"
        case .powerpoint:
            return "rectangle.3.group.fill"
        case .pages:
            return "doc.richtext.fill"
        case .numbers:
            return "tablecells.fill"
        case .keynote:
            return "rectangle.3.group.fill"

        // Audio/Video
        case .audio, .m4a, .mp3, .wav:
            return "waveform"
        case .video, .mp4, .mov:
            return "video.fill"

        case .unknown:
            return "doc.questionmark"
        }
    }
}

#Preview {
    DocumentRow(document: Document(
        filename: "Sample Document.pdf",
        fileURL: URL(fileURLWithPath: "/tmp/sample.pdf"),
        contentType: .pdf,
        totalChunks: 24
    ))
    .padding()
}
