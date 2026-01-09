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
- `sample_long.txt` - Very long document (>10,000 words)
- `sample_whitespace.txt` - Excessive whitespace and formatting

### Real-World Tests
- Add your own PDFs for real-world testing
- Recommended: 1-page, 10-page, and 100-page documents

## Testing Workflow

1. **Import a test document** via Document Library
2. **Check console logs** for:
   - Text extraction accuracy
   - Chunk count (should be ~1 chunk per 400 words)
   - Embedding generation (512 dimensions)
   - Storage confirmation
3. **Query the document** in Chat view
4. **Verify retrieval** - relevant chunks should appear

## Success Criteria

✅ All document types import without errors  
✅ Edge cases handled gracefully (not crash)  
✅ Chunks contain readable text  
✅ Queries return relevant results  
✅ Processing time <5s for most documents
