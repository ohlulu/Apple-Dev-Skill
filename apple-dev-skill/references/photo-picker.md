# Photo Picker

## API Selection (iron rule)

| Source | API | Never |
|--------|-----|-------|
| Photo library | `PHPickerViewController` (iOS 14+) | `UIImagePickerController(.photoLibrary)` |
| Camera | `UIImagePickerController(.camera)` | — (PHPicker has no camera mode) |

`UIImagePickerController`'s photo-library mode is deprecated and spawns a
fresh photo-picker XPC process on **every** presentation — measured ~3.7s
tap-to-visible on simulator, identical cold and warm, with zero visual
feedback while the user waits. `PHPickerViewController` presents in roughly
half the time cold and ~1s warm, runs out-of-process, and needs **no photo
library permission** (the extension only hands back the user's explicit
selection).

```swift
var configuration = PHPickerConfiguration()
configuration.filter = .images
configuration.selectionLimit = 1
let picker = PHPickerViewController(configuration: configuration)
picker.delegate = self
present(picker, animated: true)
```

## Delegate Traps

- **`loadObject` completion runs on a background queue.** Dispatch back to
  main before touching UI or invoking caller closures.
- **Loading can fail** (e.g. iCloud original not downloaded). Treat failure
  as a no-op, never as "no image": if the callback channel uses `nil` to
  mean "user removed the image", a failed load that sends `nil` silently
  wipes the user's existing image. Reserve `nil`/removal for the explicit
  remove action; on failure keep the current image (optionally surface an
  error).
- **Empty `results` = user cancelled.** Dismiss and do nothing — same
  no-callback contract as `imagePickerControllerDidCancel`.

```swift
public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
  picker.dismiss(animated: true)
  guard let provider = results.first?.itemProvider else { return } // cancelled

  provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
    guard let data = (object as? UIImage)?.jpegData(compressionQuality: 0.85) else { return } // failed → keep current image
    DispatchQueue.main.async {
      self?.onImagePicked?(data)
    }
  }
}
```
