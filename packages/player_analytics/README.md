# player_analytics

Client-side QoE collector for [`player_core`](../player_core). Attach it to a
`PlayerController`. You get playback **events** (including a 1s `pulse`
while playing) and a **viewend** JSON report with stability / render /
startup metrics. There is no Virtuoso or Mux backend — POST the JSON
yourself.

See [`specs/03-dart-features/analytics.md`](../../specs/03-dart-features/analytics.md).

```dart
final analytics = PlayerAnalytics.attach(
  controller,
  config: AnalyticsConfig.fromJson({'intervalMs': 1000}),
  viewerId: user.id,
  video: VideoDetails(
    id: 'ep-42',
    title: 'Episode 42',
    sourceUrl: url.toString(),
    sourceType: 'hls',
    streamType: 'vod',
  ),
  onEvent: (event) {
    // POST event.toJson() to your ingest.
  },
  onViewEnd: (report) {
    // POST report.toJsonString() — QoE is only here.
  },
);
analytics.setPlayerSize(width: 1920, height: 1080);

await controller.dispose(); // viewend
```

## License

Proprietary. See [`LICENSE`](LICENSE).
