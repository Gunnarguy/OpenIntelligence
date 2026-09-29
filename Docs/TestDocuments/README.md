# Test Documents for RAG Pipeline Validation

This directory contains test files for validating the core RAG pipeline functionality.

## Test Coverage

### Basic Functionality Tests
- `sample_1page.txt` - Single page text document
- `sample_technical.md` - Technical markdown with code blocks
- `sample_unicode.txt` - Unicode, emoji, and special characters

### Edge Case Tests
- `sample_empty.txt` - Empty document
- `sample_special_chars.txt` - Only special characters
- 2026-09-29: this list used to name `sample_long.txt`, a very long document (over 10,000 words). No such file is in this folder or in any commit (`git log --all -- '*sample_long.txt'` is empty), so the long-document case has no fixture here.
- `sample_whitespace.txt` - Excessive whitespace and formatting

### Real-World Tests
- Add your own PDFs for real-world testing
- Recommended: 1-page, 10-page, and 100-page documents

## Testing Workflow

1. **Import a test document** via Document Library
2. **Check console logs** for:
   - Text extraction accuracy
   - Chunk count (should be ~1 chunk per 300-350 words)
   - Embedding generation (384 dimensions)
   - Storage confirmation
3. **Query the document** in Chat view
4. **Verify retrieval** - relevant chunks should appear

## Success Criteria

✅ All document types import without errors
✅ Edge cases handled gracefully (not crash)
✅ Chunks contain readable text
✅ Queries return relevant results
✅ Processing time <5s for most documents
