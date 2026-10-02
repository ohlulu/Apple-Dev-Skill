# Cell Image Loading

The request lifecycle for async images in reusable views: when to cancel, what the cache key must contain, when to show synchronously, when to fade, and which thread decodes.

## When to Apply / Not for

Apply when a table / collection cell — or any reused view — shows a remote or disk image.

Not for choosing the resize API (→ [image-resizing](image-resizing.md)), not for animated images (→ [animated-image-playback](animated-image-playback.md)), and not for who owns the cell's lifecycle (→ [list-composition](list-composition.md); its row controllers call into these rules). [testing](testing.md) → "Reuse, Visibility, and Cancellation" lists the transitions to cover in tests.

Kingfisher, Nuke, and SDWebImage implement cancellation and keyed caching when used through their image-view entry point. With a library, the rules below become checks on the call site: pass the target size as a processor / transformer so it enters the cache key, and go through the per-view API so a new request replaces the previous one.

## Cancel on Every Rebind, All the Way to the Fetch

`configure(with:)` can run on a view whose previous request is still in flight: reuse after a fast scroll, `reconfigureItems`, a data refresh that rebinds a visible cell. `didEndDisplaying` and `prepareForReuse` cover none of these on their own.

1. Cancel the previous request at the start of every bind.
2. Make the cancellation reach the download. Cancelling only the decode or the assignment leaves the transfer running for an image nobody will show, and those transfers queue ahead of the images that are visible.
3. Guard the assignment anyway. A completion already scheduled on the main actor still runs after `cancel()`, so compare the item identity captured at request time with the view's current item before assigning.

```swift
final class PhotoCell: UICollectionViewCell {
    private var loadTask: Task<Void, Never>?
    private var representedID: Photo.ID?

    func configure(with photo: Photo, loader: ImageLoader, pixelSize: CGSize) {
        loadTask?.cancel()
        representedID = photo.id
        if let cached = loader.cachedImage(for: photo.url, pixelSize: pixelSize) {
            imageView.image = cached   // synchronous hit: no placeholder frame, no fade
            return
        }
        imageView.image = nil
        let start = ContinuousClock.now
        loadTask = Task { [weak self] in
            guard let image = try? await loader.image(for: photo.url, pixelSize: pixelSize),
                  let self, self.representedID == photo.id else { return }
            self.show(image, fade: ContinuousClock.now - start > .milliseconds(100))
        }
    }
}
```

The loader must honor cancellation down to its `URLSession` call (the async `URLSession` APIs do); a loader that swallows `CancellationError` turns step 2 into a no-op.

## Cache Key = Source + Everything Baked Into the Pixels

A downsampled bitmap is valid only at the pixel size it was rendered for. Key the cache by source plus pixel size, plus any processing baked into the pixels (crop, corner mask, blur). Keying by URL alone either upscales a thumbnail into a large view (blurry) or keeps a full-resolution bitmap behind a thumbnail (memory).

Consider rounding the requested width up to a handful of fixed pixel buckets, so small layout changes — rotation, split-view resize, Dynamic Type — hit the same entry instead of re-decoding. While the exact bucket loads, a cached bucket of the same source beats a blank cell.

## Show Synchronously When the Cache Has It

Check the memory cache synchronously inside `configure`, before starting async work, as in the example above. An async path always yields at least one frame of placeholder, so without the synchronous check even a 100% cache hit flickers on every reload and reconfigure.

## Fade Only Slow Loads

Consider fading in only when the image arrived after a perceptible delay (around 100 ms) and assigning faster results directly. A fade on every assignment makes reloads, reconfigures, and scroll-backs flash content that was already on screen.

## Decode Off Main, Assign on Main

A `UIImage` built from compressed data decodes lazily, at first render — on the main thread, mid-scroll. Produce the display bitmap off main at the target pixel size (ImageIO downsampling per image-resizing.md, or `byPreparingForDisplay()` for an image already at the right size) and keep only the `image` assignment on main.
