//
//  PipelineSignposts.swift
//  OpenIntelligence
//
//  Centralized signposters for the RAG pipeline.
//
//  Before this existed, `os_signpost` appeared in exactly one file
//  (RAGEngine's MMR/rerank kernels), so Instruments could show *that* time
//  was spent but not *where in the pipeline*. These signposters put named
//  interval boundaries around every major stage, which is what makes
//  on-device tracing (`xcrun xctrace record`) and the quality-mode
//  benchmark matrix able to attribute wall-clock per stage per mode.
//
//  Signposts are near-zero-cost when no recorder is attached and ship in
//  release builds by design — Instruments, not the app, decides whether
//  anything is collected.
//
//  Category conventions:
//    - Ingestion: document import, extraction, chunking, indexing
//    - Query:     retrieval-side stages (search, rerank, context packing)
//    - Synthesis: planning, generation, verification, agentic sessions
//
//  Usage at a stage boundary (two lines, no closure nesting):
//
//      let sp = PipelineSignposts.synthesis.beginInterval("MakePlan")
//      defer { PipelineSignposts.synthesis.endInterval("MakePlan", sp) }
//

import Foundation
import os

enum PipelineSignposts {
    nonisolated private static let subsystem = "Gunndamental.OpenIntelligence.Pipeline"

    /// Document import, extraction, chunking, and indexing stages.
    nonisolated static let ingestion = OSSignposter(subsystem: subsystem, category: "Ingestion")

    /// Retrieval-side stages: hybrid search, rerank, context assembly.
    nonisolated static let query = OSSignposter(subsystem: subsystem, category: "Query")

    /// Planning, generation, verification, and agentic session stages.
    nonisolated static let synthesis = OSSignposter(subsystem: subsystem, category: "Synthesis")
}
