# Third-Party Notices

## sentence-transformers/all-MiniLM-L6-v2

Source: https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
License: Apache 2.0
Used for: on-device sentence embeddings
Bundled artifact: OpenIntelligence/Resources/MLModels/EmbeddingModel.mlpackage

## cross-encoder/ms-marco-TinyBERT-L2-v2

Source: https://huggingface.co/cross-encoder/ms-marco-TinyBERT-L2-v2
License: Apache 2.0
Used for: on-device reranking
Bundled artifact: OpenIntelligence/Resources/MLModels/ReRankerModel.mlpackage

## DePasqualeOrg/swift-tokenizers

Source: https://github.com/DePasqualeOrg/swift-tokenizers
License: Apache 2.0 (Copyright 2022 Hugging Face SAS; Copyright © Anthony DePasquale)
Version: 0.7.1, revision e4e01cb59fb77c4753c6db38b4a539d624d44ce3
Used for: on-device tokenization for the two embedding providers, chunk token counts and the reranker. A Swift wrapper around Hugging Face's Rust `tokenizers` crate, linked as a prebuilt static library.
Pinned in: Package.resolved and OpenIntelligence.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
Verified: 2026-09-29, version from both Package.resolved files, license from the package's LICENSE at that revision

## huggingface/swift-transformers (vendored, reduced to a wrapper)

Source: https://github.com/huggingface/swift-transformers
License: Apache 2.0 (Copyright 2022 Hugging Face SAS), text in OpenIntelligence/swift-transformers/LICENSE
Used for: the local package TransformersTokenizers, which re-exports swift-tokenizers and carries the tokenizer file below. Its own tokenizer sources were removed on 2026-07-01 (8bc68d3).
Bundled artifact: OpenIntelligence/swift-transformers
Verified: 2026-09-29, from OpenIntelligence/swift-transformers/LICENSE, Package.swift and Sources/TokenizersWrapper/Exported.swift

## Bundled tokenizer file (tokenizer.json)

Used for: tokenizing embedding input and reranker input
Bundled artifacts: OpenIntelligence/swift-transformers/Sources/TokenizersWrapper/Resources/embedding_tokenizer.bundle/tokenizer.json and OpenIntelligence/swift-transformers/Sources/TokenizersWrapper/Resources/reranker_tokenizer.bundle/tokenizer.json, byte-identical
Format: BERT WordPiece, 30,522-entry lowercase vocabulary; padding removed and truncation raised from 128 to 512 on 2026-08-17 (2753d15)
Upstream: not recorded in this repository; the file was added on 2026-07-01 (8bc68d3) without a source. The code pairs it with the two models above (the embedding providers load embedding_tokenizer, RAGEngine loads reranker_tokenizer), both Apache 2.0, so it most likely came from one of their repositories. That is inferred, not checked against them.

## sentence-transformers/all-MiniLM-L6-v2 (Core AI export)

Source: https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
License: Apache 2.0
Used for: on-device sentence embeddings through Core AI (CoreAISentenceEmbeddingProvider)
Bundled artifact: OpenIntelligence/Resources/MLModels/EmbeddingModel.bundle
Built by: scripts/compile_core_ai_model.py, which loads sentence-transformers/all-MiniLM-L6-v2 and writes this bundle; last re-exported on 2026-08-18 (3ea5cd9)
Verified: 2026-09-29, from scripts/compile_core_ai_model.py:38 and :95 and CoreAISentenceEmbeddingProvider.swift:23 (modelRevision MiniLM-L6-v2/coreai-mlirb-meanpool)
