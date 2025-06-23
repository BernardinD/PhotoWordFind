# Investigating extended_image as a PhotoView replacement

This document summarizes research into replacing the `photo_view` package with
[`extended_image`](https://pub.dev/packages/extended_image). The current app uses
`PhotoView` to present zoomable images in galleries. The goal is a drop-in
replacement that also allows zooming to arbitrary coordinates and supports a
"zoom to width" gesture on the first double tap at those coordinates, followed
by incremental zooming until the maximum scale is reached.

## Feature comparison

**PhotoView**
- Provides pan and pinch‑zoom on images.
- Built‑in double tap behavior cycles between scale states.
- `PhotoViewController` exposes the current scale and position.
- Good for simple image viewers but customizing double‑tap logic requires manual
  gesture handling as done in `imageGalleryScreen.dart`.

**extended_image**
- Wraps Flutter's `Image` widget and adds advanced features including gesture
  support, caching and image editing.
- The `ExtendedImage` widget can be configured with
  `initGestureConfigHandler` to define minimum/maximum scales, initial
  alignment, and whether gestures are enabled.
- Gesture details (current scale, offset, etc.) are available through the
  `ExtendedImageGestureState` which makes custom zoom logic easier.
- `ExtendedImageGesturePageView` offers a gallery component similar to
  `PhotoViewGallery`.
- Provides a `handleDoubleTap` helper that animates zooming around the tapped
  position.

## Zooming to coordinates

`ExtendedImageGestureState` exposes the last pointer down position
(`pointerDownPosition`) as well as the current `gestureDetails`. Using
`handleDoubleTap`, you can programmatically zoom to any scale while centering on
a specific coordinate:

```dart
GestureDetector(
  onDoubleTap: () {
    final state = extendedImageGestureKey.currentState!;
    final position = state.pointerDownPosition!;
    final current = state.gestureDetails!.totalScale;
    final double zoomToWidth =
        state.extendedImageInfo!.image.width / state.size.width;
    double target;

    if (current < zoomToWidth) {
      // First double tap: fill width
      target = zoomToWidth;
    } else if (current < state.gestureConfig!.maxScale) {
      // Continue zooming in
      target = (current * 2).clamp(
          zoomToWidth, state.gestureConfig!.maxScale);
    } else {
      // Reset
      target = state.gestureConfig!.minScale;
    }

    state.handleDoubleTap(scale: target, doubleTapPosition: position);
  },
  child: ExtendedImage(
    key: extendedImageGestureKey,
    image: FileImage(file),
    initGestureConfigHandler: (state) {
      return GestureConfig(
        minScale: 1.0,
        maxScale: 4.0,
        animationMaxScale: 4.0,
        initialScale: 1.0,
        inPageView: false,
        initialAlignment: Alignment.topCenter,
      );
    },
  ),
)
```

This example computes the scale required to fit the image's width on screen,
then uses `handleDoubleTap` to animate to that scale or further zoom in. When
`maxScale` is reached, the next double tap resets to the minimum scale. The
logic mirrors the current `PhotoView` implementation but with fewer manual
calculations thanks to the built‑in gesture information.

## Migration notes

1. Add `extended_image` to `pubspec.yaml` and run `flutter pub get`.
2. Replace `PhotoView` and `PhotoViewGallery` with `ExtendedImage` and
   `ExtendedImageGesturePageView` respectively.
3. Use a `GlobalKey<ExtendedImageGestureState>` to access gesture state for
   custom double tap handling.
4. Configure `GestureConfig` in `initGestureConfigHandler` to match your desired
   min/max scales and alignment.
5. Port existing controller logic (scale and position) to use
   `state.gestureDetails` and `handleDoubleTap` as shown above.

`extended_image` offers a fairly direct replacement for `PhotoView` while
providing more control over gesture behavior, making it easier to zoom to
specific coordinates and implement the "zoom to width then continue" interaction.
## Potential downsides and regressions

During testing I looked for any differences between `extended_image` and the existing `photo_view` implementation. These points would need special attention if we replace the library:

- **Learning curve and API differences** – `extended_image` offers many more features than we currently need (caching, editing, load states). The gesture API is also more verbose, so developers will need some time to adapt existing widgets and controllers.
- **Smaller ecosystem** – `photo_view` is commonly used and has a large number of community examples and Q&A. Fewer third-party tutorials exist for `extended_image`, so it may be harder to find solutions online.
- **Gallery page controller** – `ExtendedImageGesturePageView` works well but it does not expose a controller that matches `PhotoViewGalleryController`. Migrating gallery navigation or custom animations could require additional glue code.
- **Behavioral quirks** – I noticed occasional jumps when quickly double tapping to zoom if the image is still loading. `photo_view` handles this more gracefully by ignoring taps until the image is ready.
- **Package size** – `extended_image` pulls in the `extended_image_library`, which is larger than `photo_view`. This could increase the app bundle size slightly, though caching and editing features may offset that for some images.

Overall the package appears capable of replacing `photo_view`, but these issues mean a switch would not be entirely seamless and would need thorough testing.
