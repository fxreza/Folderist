# Base folder artwork

Drop the base folder bitmap here. It is the artwork every icon is built from: the default style
renders it **untouched**, and every coloured style is a per-pixel HSB remap of these very pixels,
so the folds, the white paper peek and the baked drop shadow all survive.

## What to drop in

| File | Notes |
| --- | --- |
| `BaseFolder.icns` | Preferred. Each icon size is served from the representation drawn for it, so no size is ever a resample. |
| `BaseFolder.png` | A square master, 1024 × 1024 px. Smaller sizes are downscaled from it. |
| `BaseFolder-empty.png` | Optional alternate artwork (`BaseFolderArt.load(directory:name:)`). |

`.tiff` and `.heic` are accepted too. The bitmap must be square, with a transparent surround and
its own drop shadow baked in — the renderer adds no shadow of its own in bitmap mode.

## What happens when this directory is empty

Nothing breaks. `BaseFolderArt` falls back, in order, to:

1. the **system folder icon**, read off the running Mac at launch
   (`NSWorkspace.icon(for: .folder)`, then Apple's `GenericFolderIcon.icns` inside
   `/System/Library/CoreServices/CoreTypes.bundle`);
2. the **vector `FolderGeometry` pipeline**, our own rebuilt folder shape.

Apple's artwork is only ever read at runtime from the user's own Mac. Do not commit it here.

## After adding artwork

`StyleColor.folderBlue` is the sentinel the renderer compares a style's fill against to decide
"this is the default, emit the bitmap untouched". Set it to the artwork's own measured colour:

```swift
BaseFolderArt.load(directory: url)?.dominantColor()   // → StyleColor(red:green:blue:)
```

`swift test --filter "Base folder artwork"` prints that value for whatever artwork it can find.
