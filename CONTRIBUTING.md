# Contributing to OpenIntelligence

Thank you for your interest in contributing to OpenIntelligence! We aim to build the reference implementation for privacy-first RAG on iOS, and your help is vital.

## 🌟 The "10x" Standard

We strive for excellence in code quality, architecture, and documentation.

- **Protocol-First**: Always define behavior via protocols before implementation.
- **Actor Isolation**: Heavy compute goes to `RAGEngine` (actor) or background Tasks.
- **Privacy-First**: No data leaves the device without explicit, logged consent.
- **Zero Warnings**: The project should build with zero warnings in Release mode.

## 🛠 Development Workflow

1. **Fork & Clone**

   ```bash
   git clone https://github.com/yourusername/OpenIntelligence.git
   cd OpenIntelligence
   ```

2. **Open in Xcode 26+**
   - Ensure you have the iOS 26.0+ SDK installed.
   - Select the `OpenIntelligence` scheme.

3. **Branching Strategy**
   - `main`: Production-ready code.
   - `feature/your-feature`: New capabilities.
   - `fix/bug-description`: Bug fixes.

4. **Building**
   - Use `Cmd+B` to build.
   - Use `./clean_and_rebuild.sh` if you encounter DerivedData issues.

## 🧪 Testing

### Smoke Tests

Before submitting a PR, you **must** run the manual smoke test procedure:

1. Read `smoke_test.md`.
2. Ingest the `Docs/TestDocuments/` folder.
3. Verify chat responses and telemetry badges.

### Unit Tests

(Coming soon - we are currently prioritizing the reference architecture)

## 📝 Pull Request Guidelines

1. **Descriptive Title**: Use the format `[Area] Description` (e.g., `[RAG] Fix MMR diversity calculation`).
2. **Screenshots/Video**: For UI changes, attach a recording.
3. **Architecture Impact**: If you change `RAGService` or `LLMService`, explain why in the PR description.
4. **No Breaking Changes**: Ensure existing document stores remain readable or provide a migration path.

## 🎨 Style Guide

- **Swift 6**: Use strict concurrency checking.
- **Formatting**: We follow standard Swift API Design Guidelines.
- **Comments**: Document complex logic, especially in `RAGEngine` math functions.
- **TODOs**: Mark incomplete work with `// TODO: [User] Description`.

## ⚖️ License

By contributing, you agree that your contributions will be licensed under the MIT License.
