# Image Resizing

## Core Principle

Choose the resize API based on **what happens to the image after resizing**. Display-only and encode-to-data have different correct answers.

## Decision Rule

| After resize you… | Use | Why |
|---|---|---|
| Display in a `UIImageView` / `UIButton` | `UIGraphicsImageRenderer` | Default choice; handles scale, color space, HDR automatically |
| Encode to JPEG/PNG for upload or storage | `preparingThumbnail(of:)` (iOS 15+) | Actually resizes the underlying `CGImage` — export is smaller |
| Downsample a large file from disk | `CGImageSourceCreateThumbnailAtIndex` | Fastest; never decodes full image into memory |
| Batch process in an existing Accelerate pipeline | `vImage` | Only if already in that stack |

Do **not** use Core Image (`CILanczosScaleTransform`) for resizing — it is ~15× slower than UIKit/ImageIO for scale-only operations.

## `UIGraphicsImageRenderer` — Display Resize

The standard, recommended API for resizing images that will be displayed on screen.

```swift
func resized(to size: CGSize) -> UIImage {
    UIGraphicsImageRenderer(size: size).image { _ in
        draw(in: CGRect(origin: .zero, size: size))
    }
}
```

**How scale works**: `UIGraphicsImageRenderer` uses **point size** by default. On a 2× display, passing `CGSize(width: 32, height: 32)` produces a 64×64 pixel bitmap. This is the correct behavior for display.

To get exact pixel output (e.g., generating an asset at 1×), set `format.scale = 1`:

```swift
let format = UIGraphicsImageRendererFormat()
format.scale = 1 // 1 point = 1 pixel
let renderer = UIGraphicsImageRenderer(size: size, format: format)
```

### The Export Gotcha

`UIGraphicsImageRenderer` resizes the **logical UIImage**, but the underlying `CGImage` may retain the original resolution. Calling `.jpegData()` or `.pngData()` on the result can produce a file as large as the original.

This does **not** matter when the resized image is only used for display. It matters when you encode to data — use `preparingThumbnail` instead for that path.

## `preparingThumbnail(of:)` — Encode-Safe Resize

iOS 15+. Actually resizes the underlying pixel buffer, so JPEG/PNG export reflects the new size.

```swift
// Synchronous
let thumb = image.preparingThumbnail(of: CGSize(width: 200, height: 200))

// Async
let thumb = await image.byPreparingThumbnail(ofSize: CGSize(width: 200, height: 200))
```

### Caveats

- **Size is in pixels, not points.** Multiply by `displayScale` for Retina-crisp output:
  ```swift
  let scale = UIScreen.main.scale
  let thumb = image.preparingThumbnail(of: CGSize(width: 200 * scale, height: 200 * scale))
  ```
- **Does not preserve aspect ratio.** Caller must compute proportional dimensions.
- **Two internal code paths** (confirmed via reverse engineering): file-URL-backed images get a fast `CGImageSource` path (~24ms); `UIImage(data:)` images get a slower private path (~130ms) that can be slower than `UIGraphicsImageRenderer`.
- **No macOS equivalent** — iOS/iPadOS only.

## `CGImageSourceCreateThumbnailAtIndex` — Disk-Based Downsampling

Fastest option for large images loaded from file. Avoids decoding the full image into memory.

```swift
func downsample(fileURL: URL, to maxPixelSize: CGFloat) -> UIImage? {
    let options: [CFString: Any] = [
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return UIImage(cgImage: cgImage)
}
```

**Memory impact**: A 12,000px image uses ~220 MB without downsampling vs. ~24 MB with — nearly 10× reduction.

Use this when loading user photos from disk (camera roll, file imports) for display in thumbnails or lists.

## Template Icon Resizing

For small vector icons (PDF assets, Tabler icons) used in buttons and toolbars, `UIGraphicsImageRenderer` is the correct choice — same `UIGraphicsImageRenderer(size:).image { draw(in:) }` pattern as the Display Resize section above, with the result passed through `.withRenderingMode(.alwaysTemplate)` so the icon tints with `tintColor` instead of rendering its own fixed colors.

This is correct because:
- PDF icons are small — no memory concern, no performance concern.
- The image is display-only — the export gotcha is irrelevant.
- `UIGraphicsImageRenderer` respects screen scale automatically — crisp on all devices.
- `preparingThumbnail` is designed for photo downsampling — overkill for a 24pt icon.
- `preparingThumbnail`'s fast path requires file-URL-backed images; `UIImage(named:)` assets go through the slow path, making it actually slower than `UIGraphicsImageRenderer` for this case.

## Summary

| API | Min iOS | Scale | Resizes CGImage | Best For |
|---|---|---|---|---|
| `UIGraphicsImageRenderer` | 10 | Points (auto ×2/×3) | ❌ Logical only | Display: icons, buttons, image views |
| `preparingThumbnail(of:)` | 15 | Pixels (manual scale) | ✅ | Encode to JPEG/PNG for upload/storage |
| `CGImageSourceCreateThumbnailAtIndex` | 5 | Pixels | ✅ | Large photos from disk; lowest memory |
