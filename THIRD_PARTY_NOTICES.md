# Third-Party Notices

## sentence-transformers/all-MiniLM-L6-v2

Source: https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
License: Apache 2.0
Used for: on-device sentence embeddings
Bundled artifact: OpenIntelligence/Resources/MLModels/EmbeddingModel.mlpackage
Training data (open defect under the commercial-use rule, `Docs/ai/PURPOSE.md` rule 1): the model card lists 9,144,553 MS MARCO triplets among its training data, and MS MARCO's terms are for non-commercial research. Its replacement, ibm-granite/granite-embedding-small-english-r2, was measured on 2026-11-09 (`BenchmarkRuns/2026-11-09-reranker-swap/`); swapping it means re-embedding every library, which waits on the owner's decision.

## ibm-granite/granite-embedding-reranker-english-r2

Source: https://huggingface.co/ibm-granite/granite-embedding-reranker-english-r2, revision d09d3d6971b689bf9c23839e45a470874d46e13a
License: Apache 2.0 (Copyright IBM), text at https://www.apache.org/licenses/LICENSE-2.0
Training data: the model card says IBM does not use MS MARCO "due to its non-commercial license", and lists web title-body pairs, public data under permissive licences, IBM-internal data and IBM-generated synthetic data (read 2026-11-09 at the revision above).
Used for: on-device reranking, since 5.8
Bundled artifact: OpenIntelligence/Resources/MLModels/ReRankerModel.mlpackage (converted to Core ML, two fixed-shape functions, weights palettized to 4 bits, which rounds each weight to one of 16 values per group; otherwise IBM's weights unchanged)
Built by: scripts/build_reranker_model.py
Replaced: cross-encoder/ms-marco-TinyBERT-L2-v2 (Apache 2.0, trained on MS MARCO), bundled through 5.7

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

## Bundled tokenizer files (tokenizer.json)

Reranker: OpenIntelligence/swift-transformers/Sources/TokenizersWrapper/Resources/reranker_tokenizer.bundle/tokenizer.json is, since 5.8, the tokenizer of ibm-granite/granite-embedding-reranker-english-r2 at the revision above (Apache 2.0): byte-pair encoding, 50,280-entry vocabulary plus 116 added tokens, with its built-in truncation and padding removed by scripts/build_reranker_model.py so the app's code sets both.

Embedder, below. Through 5.7 the reranker's file was a byte-identical copy of it.

Used for: tokenizing embedding input
Bundled artifacts: OpenIntelligence/swift-transformers/Sources/TokenizersWrapper/Resources/embedding_tokenizer.bundle/tokenizer.json
Format: BERT WordPiece, 30,522-entry lowercase vocabulary; padding removed and truncation raised from 128 to 512 on 2026-08-17 (2753d15)
Upstream: not recorded in this repository; the file was added on 2026-07-01 (8bc68d3) without a source. The code pairs it with the two models above (the embedding providers load embedding_tokenizer, RAGEngine loads reranker_tokenizer), both Apache 2.0, so it most likely came from one of their repositories. That is inferred, not checked against them.

## sentence-transformers/all-MiniLM-L6-v2 (Core AI export)

Source: https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
License: Apache 2.0
Used for: on-device sentence embeddings through Core AI (CoreAISentenceEmbeddingProvider)
Bundled artifact: OpenIntelligence/Resources/MLModels/EmbeddingModel.bundle
Built by: scripts/compile_core_ai_model.py, which loads sentence-transformers/all-MiniLM-L6-v2 and writes this bundle; last re-exported on 2026-08-18 (3ea5cd9)
Verified: 2026-09-29, from scripts/compile_core_ai_model.py:38 and :95 and CoreAISentenceEmbeddingProvider.swift:23 (modelRevision MiniLM-L6-v2/coreai-mlirb-meanpool)
