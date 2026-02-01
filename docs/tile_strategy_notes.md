# Fixed-Tile Overlap Strategy

## Premise
- Goal: preserve legibility from long scroll screenshots without reverting to single-image downscaling or paying unbounded per-request costs.
- Constraint: OpenAI vision billing is per image, proportional to 32x32 patches, capped at 1,536 patches per image after automatic downscale.
- Insight: Pick a constant tile count (for example 5) so request cost is predictable while still keeping each tile near native quality.

## Approach
1. Decode the screenshot once (already required for any preprocessing).
2. Choose an overlap ratio (default 25%).
3. Solve for a chunk height that yields exactly N tiles when combined with that overlap:
   - `chunkHeight ~ H / (1 + (N - 1) * (1 - overlap))`, clamp so `chunkHeight <= width` to keep square-ish tiles.
   - `stride = chunkHeight * (1 - overlap)`.
4. Loop `i = 0..N-1`, crop `[0, i * stride, width, chunkHeight]`, clamping the last tile to the bottom of the source image so coverage is complete.
5. For each tile, ensure `ceil(width/32) * ceil(chunkHeight/32) <= 1,536`. If width alone exceeds the cap, downscale width once before cropping to avoid the API shrinking each tile independently.
6. Base64-encode the N tiles and send all within a single chat completion request.

## Trade-offs
- Pros: predictable per-request image-token spend (`<= N * 1,536`), better text fidelity than a fully downscaled single screenshot, simpler queueing than variable tile counts.
- Cons: still more expensive than the original single-image pipeline; tiles with mostly blank space waste patches; requires runtime math to guard against width > cap.
- Operational: overlap increases redundant pixels roughly by `1 / (1 - overlap)`; consider lowering overlap for tall uniform text to keep total area closer to `N * chunkHeight`.

## Notes / Next Steps
- Expose `N`, overlap, and optional width clamp in settings for experimentation.
- Log estimated vs. actual image_token_count so future tweaks have data.
- If certain screenshots need more than N tiles, fall back to the original single-image upload rather than silently exceeding the fixed budget.

## Findings - 2026-02-01
- Swapping the tiling pipeline from `gpt-4o-mini` to `gpt-4.1-mini` dropped per-request image costs from roughly $0.40 (≈400k input tokens at $2.50/M) to ≈$0.016 (same tokens at $0.40/M) while keeping clarity acceptable.
- Requests now consistently log ~10k billable image tokens for five tiles, matching the fixed-count math and confirming that volume stayed constant; the savings are purely from GPT-4.1 mini's lower pricing.
- One sampled import showed a Snapchat handle present in `sections` text but missing from `social_media_handles`, so additional debugging/logging is required to understand why post-processing doesn't pick it up.
