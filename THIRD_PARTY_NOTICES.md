# Third-Party Notices

## ibm-granite/granite-embedding-small-english-r2

Source: https://huggingface.co/ibm-granite/granite-embedding-small-english-r2, revision 2ab6fa8e
License: Apache 2.0 (Copyright IBM), text at https://www.apache.org/licenses/LICENSE-2.0
Training data: the model card says IBM leaves out MS MARCO for its non-commercial licence, and lists permissively licensed public data, IBM-internal data and IBM-generated synthetic data; it also names "select proprietary data", which rests on IBM's statement.
Used for: on-device sentence embeddings, since 5.8
Bundled artifact: OpenIntelligence/Resources/MLModels/EmbeddingModel.mlpackage (converted to Core ML with two fixed-length functions, 256 and 512 tokens, CLS pooling and L2 normalisation in the graph, weights quantized to 8 bits per channel; otherwise IBM's weights unchanged)
Built by: scripts/build_embedding_model.py
Replaced: sentence-transformers/all-MiniLM-L6-v2 (Apache 2.0 weights, trained on 9,144,553 MS MARCO triplets, whose terms are for non-commercial research), bundled through 5.7 in a Core ML copy and a Core AI copy (OpenIntelligence/Resources/MLModels/EmbeddingModel.bundle, which since 5.8 holds only a README)

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

Embedder: OpenIntelligence/swift-transformers/Sources/TokenizersWrapper/Resources/embedding_tokenizer.bundle/tokenizer.json is, since 5.8, the tokenizer of ibm-granite/granite-embedding-small-english-r2 at the revision above (Apache 2.0): byte-pair encoding, 50,280-entry vocabulary plus 116 added tokens, truncation and padding removed by scripts/build_embedding_model.py. Through 5.7 it was a BERT WordPiece file of 30,522 entries for MiniLM, added on 2026-07-01 (8bc68d3) without a recorded source.

## mozilla/uniffi-rs, as patched by DePasqualeOrg (inside swift-tokenizers' static library)

Source: https://github.com/DePasqualeOrg/uniffi-rs at e3e99802532ba76887b21a38de926dd55f469d48 (uniffi 0.31.1: uniffi, uniffi_core, uniffi_macros, uniffi_meta, uniffi_bindgen, uniffi_pipeline, uniffi_udl, uniffi_internal_macros)
License: Mozilla Public License 2.0, text at https://www.mozilla.org/en-US/MPL/2.0/ ; its source, including the patch, is public at the address above. weedle2 5.0.0 from the same repository is MIT.
Used for: the Swift-to-Rust bridge of swift-tokenizers, linked as a prebuilt static library

## Rust crates in swift-tokenizers' static library

About 150 further crates (Hugging Face `tokenizers` and its dependencies) are under MIT and/or Apache 2.0, with a few under Unlicense, Zlib, BSD-2-Clause, BSL-1.0 or Unicode-3.0, all permissive. The per-crate list was read on 2026-11-12 from the package's Cargo.lock; their copyright notices are not yet shown in the app (Future Backlog).

Verified 2026-11-12 (licence audit, read-only): no bundled model, package or asset is under a non-commercial licence. One image in the asset catalogue, LogicBoard_A18Pro, had no recorded source or licence and no code read it; it was removed the same day.
