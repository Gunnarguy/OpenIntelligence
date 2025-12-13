# Test Setup Guide

## Adding the Test Target to Xcode

The `OpenIntelligenceTests` folder contains unit tests, but they need to be added to the Xcode project.

### Steps to Add the Test Target

1. **Open the project in Xcode**
   ```bash
   open OpenIntelligence.xcodeproj
   ```

2. **Add the Test Target**
   - Go to **File → New → Target**
   - Select **iOS Unit Testing Bundle**
   - Name it: `OpenIntelligenceTests`
   - Ensure "Host Application" is set to `OpenIntelligence`
   - Click **Finish**

3. **Add Existing Test Files**
   - Delete the auto-generated test file in the new group
   - Right-click the `OpenIntelligenceTests` group in the Project Navigator
   - Select **Add Files to "OpenIntelligence"...**
   - Navigate to the `OpenIntelligenceTests` folder
   - Select all `.swift` files:
     - `TestDoubles.swift`
     - `RAGPipelineTests.swift`
     - `HybridSearchServiceTests.swift`
     - `StoreKitEntitlementTests.swift`
     - `VectorDatabaseTests.swift`
     - `VectorStoreRouterTests.swift`
     - `EmbeddingDiagnosticsTests.swift`
   - Ensure "Copy items if needed" is **unchecked**
   - Ensure target membership is `OpenIntelligenceTests`
   - Click **Add**

4. **Configure the Scheme for Testing**
   - Go to **Product → Scheme → Edit Scheme...**
   - Select **Test** in the sidebar
   - Click **+** under "Test Plans" or "Info"
   - Add `OpenIntelligenceTests` target
   - Close the dialog

5. **Share the Scheme (for CI)**
   - Go to **Product → Scheme → Manage Schemes...**
   - Check the **Shared** checkbox next to `OpenIntelligence`
   - This creates `xcshareddata/xcschemes/OpenIntelligence.xcscheme`

### Running Tests

After setup, run tests via:

```bash
# Xcode GUI
⌘U

# Command Line
xcodebuild test \
  -scheme OpenIntelligence \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

### Test Coverage

| Test File | Purpose |
|-----------|---------|
| `TestDoubles.swift` | Mock/Stub implementations for testing |
| `RAGPipelineTests.swift` | End-to-end RAG pipeline tests |
| `HybridSearchServiceTests.swift` | BM25 + Vector fusion tests |
| `StoreKitEntitlementTests.swift` | Entitlement and billing tests |
| `VectorDatabaseTests.swift` | Vector storage and search tests |
| `VectorStoreRouterTests.swift` | Container routing tests |
| `EmbeddingDiagnosticsTests.swift` | Embedding service tests |

### CI Configuration

The GitHub Actions workflow in `.github/workflows/ci.yml` expects the test scheme to be shared. After completing the above steps, commit the generated scheme file:

```bash
git add OpenIntelligence.xcodeproj/xcshareddata/
git commit -m "Add shared scheme with test configuration"
```
