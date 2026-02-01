# Width-Square Overlap Strategy

## Premise
- Goal: preserve legibility from long scroll screenshots without reverting to single-image downscaling or paying unbounded per-request costs.
- Constraint: OpenAI vision billing is per image, proportional to 32x32 patches, capped at 1,536 patches per image after automatic downscale.
- Insight: Slice each screenshot into width-sized squares with overlap so every tile preserves native-width text without having to reason about arbitrary crop rectangles.

## Approach
1. Decode the screenshot once (already required for any preprocessing).
2. Choose an overlap ratio (default 25%).
3. Set `chunkHeight = min(width, height)` so tiles are square when the screenshot is taller than it is wide.
4. Compute `stride = chunkHeight * (1 - overlap)`, clamping to at least 1 pixel.
5. Slide from top to bottom, cropping `[0, safeY, width, chunkHeight]` until reaching the end of the screenshot. The number of tiles is therefore dynamic and depends on the scroll length.
6. For each tile, ensure `ceil(width/32) * ceil(chunkHeight/32) <= 1,536`. If width alone exceeds the cap, downscale width once before cropping to avoid the API shrinking each tile independently.
7. Base64-encode all tiles from the loop and send them in the same chat completion request.

## Trade-offs
- Pros: preserves native-width sharpness automatically, overlap ensures OCR continuity, code remains simple (fixed width and stride math).
- Cons: tile count grows with screenshot height so image-token spend still scales linearly with scroll length; tiles with mostly blank space waste patches; requires runtime math to guard against width > cap.
- Operational: overlap increases redundant pixels roughly by `1 / (1 - overlap)`; consider lowering overlap for tall uniform text to keep total area closer to `chunkHeight / stride`.

## Notes / Next Steps
- Expose overlap ratio and optional width clamp in settings for experimentation.
- Log estimated vs. actual image_token_count so future tweaks have data.
- Explore an optional fixed-N mode (as originally planned) to cap cost when screenshots are extremely tall.
- If certain screenshots would exceed a chosen budget, fall back to the original single-image upload rather than silently exceeding the fixed budget.

## Findings - 2026-02-01
- Swapping the tiling pipeline from `gpt-4o-mini` to `gpt-4.1-mini` dropped per-request image costs from roughly $0.40 (≈400k input tokens at $2.50/M) to ≈$0.016 (same tokens at $0.40/M) while keeping clarity acceptable.
- Requests now consistently log ~10k billable image tokens for five tiles, matching the fixed-count math and confirming that volume stayed constant; the savings are purely from GPT-4.1 mini's lower pricing.
- One sampled import showed a Snapchat handle present in `sections` text but missing from `social_media_handles`, so additional debugging/logging is required to understand why post-processing doesn't pick it up.
