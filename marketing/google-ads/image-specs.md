# Image Asset Specifications

Google App Campaigns require multiple image sizes for optimal placement across networks.

## Required Image Sizes

### Landscape (Priority 1)

| Size           | Ratio   | Use Case                  |
| -------------- | ------- | ------------------------- |
| **1200 × 628** | 1.91:1  | Display Network, Discover |
| 1200 × 627     | ~1.91:1 | Alternative               |

### Square (Priority 2)

| Size            | Ratio | Use Case         |
| --------------- | ----- | ---------------- |
| **1200 × 1200** | 1:1   | YouTube, Display |
| 300 × 300       | 1:1   | Minimum required |

### Portrait (Priority 3)

| Size            | Ratio | Use Case             |
| --------------- | ----- | -------------------- |
| **1200 × 1500** | 4:5   | Feed placements      |
| 480 × 800       | 3:5   | Mobile interstitials |

## File Requirements

- **Format**: PNG or JPG
- **Max file size**: 5 MB per image
- **Max images**: 20 per ad group
- **Min images**: 1 landscape, 1 square (recommended: all 3 orientations)

## Creative Guidelines

### DO ✅

- Show app UI/screenshots
- Include clear app icon
- Use high contrast text overlays
- Show the "magic moment" (asking a question → getting an answer)
- Feature real document types (PDFs, manuals, textbooks)

### DON'T ❌

- Use more than 20% text coverage
- Include App Store badges in images
- Use misleading UI elements
- Show competitor logos/names
- Use stock photos without context

## Suggested Image Concepts

1. **Split Screen**: Document on left → AI answer on right
2. **Before/After**: Stack of documents → Single chat answer
3. **Hero Shot**: iPhone with app UI, privacy lock icon overlay
4. **Use Case**: Student with laptop, professional with iPad
5. **Feature Grid**: Icons showing PDF, Privacy, Speed, AI

## Naming Convention

```
openintelligence_[size]_[concept]_v[version].png

Examples:
openintelligence_1200x628_splitscreen_v1.png
openintelligence_1200x1200_privacy_v2.png
openintelligence_1200x1500_student_v1.png
```

## Quick Export Checklist

- [ ] 1200×628 landscape (required)
- [ ] 1200×1200 square (required)
- [ ] 1200×1500 portrait (recommended)
- [ ] All images < 5MB
- [ ] No text > 20% of image area
- [ ] No App Store badges
