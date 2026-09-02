# Virtuoso Player SDK

Proprietary binary SDK. Dart API plus Android AAR / iOS XCFramework.
No engine source is included.

```yaml
dependencies:
  player_core:
    git:
      url: https://github.com/sidcasmm/virtuoso-sdk.git
      path: packages/player_core
      ref: v1.0.0
```

Activate before creating players:

```dart
await PlayerLicense.activate('<token>');
```

See LICENSE. Do not publish these packages.
