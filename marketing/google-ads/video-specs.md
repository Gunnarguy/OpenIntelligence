# Video Asset Specifications

Video assets are **critical** for App campaign performance. Portrait videos have 60% higher conversion rates.

## Required Video Formats

### Portrait (Highest Priority) 📱

| Aspect Ratio | Resolution | Duration | Use Case                |
| ------------ | ---------- | -------- | ----------------------- |
| **9:16**     | 1080×1920  | 15-30s   | YouTube Shorts, Stories |
| **2:3**      | 1080×1620  | 15-30s   | Feed placements         |

### Square

| Aspect Ratio | Resolution | Duration | Use Case      |
| ------------ | ---------- | -------- | ------------- |
| **1:1**      | 1080×1080  | 15-30s   | Display, Feed |

### Landscape

| Aspect Ratio | Resolution | Duration | Use Case          |
| ------------ | ---------- | -------- | ----------------- |
| **16:9**     | 1920×1080  | 15-30s   | YouTube in-stream |

## Technical Requirements

- **Format**: MP4 (H.264 codec)
- **Max file size**: 1 GB
- **Max duration**: 60 seconds (15-30s recommended)
- **Min duration**: 10 seconds
- **Audio**: AAC, 128kbps+
- **Frame rate**: 24-60 fps

## Video Structure (15-30 seconds)

```
[0-3s]   HOOK: Problem or attention grabber
[3-10s]  DEMO: Show app solving the problem
[10-20s] FEATURES: Key benefits (privacy, speed)
[20-25s] SOCIAL PROOF: "Join thousands..." (optional)
[25-30s] CTA: "Download free on App Store"
```

## Script Templates

### Template 1: Problem → Solution (15s)

```
[0-3s]   "Drowning in documents?"
[3-8s]   [Show: importing PDF]
[8-12s]  [Show: asking question, getting answer]
[12-15s] "OpenIntelligence. Download free."
```

### Template 2: Demo Focus (20s)

```
[0-2s]   [Show: iPhone with app]
[2-7s]   "Import any document..."
[7-12s]  "Ask any question..."
[12-17s] "Get cited answers. 100% private."
[17-20s] "Try it free."
```

### Template 3: Privacy Focus (15s)

```
[0-3s]   "Your documents. Your device."
[3-8s]   [Show: lock icon, on-device processing]
[8-12s]  "AI that never uploads your data."
[12-15s] "OpenIntelligence. Download now."
```

## Best Practices

### DO ✅

- Start with motion/action in first 3 seconds
- Show actual app UI (screen recordings)
- Include captions (85% watch without sound)
- End with clear CTA + app icon
- Use portrait orientation for best performance

### DON'T ❌

- Start with static logo
- Use only stock footage
- Exceed 30 seconds for top-of-funnel
- Forget mobile-first framing
- Use tiny text unreadable on mobile

## Recommended Video Variations

| #   | Concept              | Orientation | Duration |
| --- | -------------------- | ----------- | -------- |
| 1   | App demo walkthrough | Portrait    | 20s      |
| 2   | Problem → Solution   | Portrait    | 15s      |
| 3   | Privacy messaging    | Square      | 15s      |
| 4   | Feature highlights   | Landscape   | 30s      |
| 5   | Testimonial style    | Portrait    | 20s      |

## Naming Convention

```
openintelligence_[ratio]_[concept]_[duration]s_v[version].mp4

Examples:
openintelligence_9x16_demo_20s_v1.mp4
openintelligence_1x1_privacy_15s_v1.mp4
openintelligence_16x9_features_30s_v2.mp4
```

## Upload Checklist

- [ ] At least 1 portrait (9:16 or 2:3)
- [ ] At least 1 square (1:1)
- [ ] At least 1 landscape (16:9)
- [ ] All videos have captions/text
- [ ] Clear CTA in final 3 seconds
- [ ] App icon visible at end
- [ ] Audio optional but quality if included
