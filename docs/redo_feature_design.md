# Redo Feature Design

The redo feature lets a user highlight any portion of an existing photo and re-run text extraction on just that snippet. It modernizes the older fixed-square cropping dialog with a flexible overlay that matches Material design guidelines.

This document outlines a modern approach for the **Redo** feature in the new PhotoWordFind UI.

## Legacy Behavior
In the old interface a user would open the image's popup menu and select **Redo**. The app displayed an `AlertDialog` with the picture inside a fixed square `RepaintBoundary`. Tapping the **REDO** button captured that region and re-ran OCR on it.

While functional, the dialog felt dated and did not provide flexible cropping controls or guidance.

## New UX Concept
The redo action focuses on re‑processing text from a specific region of an image. The updated design embraces Material 3 principles and modern UX patterns:

1. **Full‑screen cropping overlay**
   - Selecting **Redo text extraction** from the image menu opens a full‑screen view of the original image.
   - A resizable crop box with drag handles lets the user define the exact area to analyze.
   - Pinch‑to‑zoom and panning allow fine-grained positioning without leaving the crop mode.
2. **Bottom action bar**
   - A floating action bar at the bottom provides **Cancel** and **Redo** buttons.
   - Tapping outside the image or pressing Cancel exits crop mode without changes.
   - The bar uses a subtle elevation and adapts to light/dark themes for clear visibility.
3. **Inline guidance and progress**
   - A short hint appears the first time explaining that the region will be scanned again.
   - After pressing **Redo**, a progress indicator shows while OCR runs in the background.
   - When finished, the gallery item updates with the new extracted text and the overlay closes automatically.

## Interaction Flow
1. Long‑press an image or open its menu and choose **Redo text extraction**.
2. The image expands into a full‑screen crop interface.
3. Drag the handles to frame the desired text portion; zoom and pan as needed.
4. Tap **Redo** in the bottom bar to submit the region for OCR.
5. A brief loading indicator appears. Once complete, the user returns to the gallery with updated text for that photo.

This approach keeps the user in context, offers precise control over the crop area and aligns with modern Material You design practices.

The existing implementation lives in `gallery_cell.dart` as `showRedoWindow()`. This document proposes replacing that dialog with the overlay workflow above.
