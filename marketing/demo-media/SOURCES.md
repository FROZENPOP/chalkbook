# Demo media sources

Every image here was drawn by us with Core Graphics in `render_demo_media.swift` (no photos, no people, no third-party assets).
License: made for this project; no attribution required.
Regenerate with `swift marketing/demo-media/render_demo_media.swift marketing/demo-media`.

Used only by `scripts/capture_store_screenshots.sh`, which passes this folder to the Debug app as `CHALKBOOK_DEMO_MEDIA`. Nothing here is in the app target.

| File | What it is | Source |
|---|---|---|
| `wall-pink.jpg`, `wall-blue.jpg`, `wall-green.jpg`, `wall-yellow.jpg`, `wall-purple.jpg` | Rendered bouldering walls with one route's holds in the named color; the start hold is at (0.5, 0.86). Route photos in the demo journal (highlighted in the app). | `render_demo_media.swift` |
| `wall-*-highlighted.jpg` | The same walls with every other hold dimmed, as the shared highlighted photo in Friends posts. | `render_demo_media.swift` |
| `avatar.jpg` | Made-up climber silhouette on a boulder at dusk, the demo profile photo. | `render_demo_media.swift` |
