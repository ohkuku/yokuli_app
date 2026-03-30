// Conditional export:
//   dart.library.html  → web browser  → lan_sync_platform_web.dart
//   (default)          → native        → lan_sync_platform_native.dart
export 'lan_sync_platform_native.dart'
    if (dart.library.html) 'lan_sync_platform_web.dart';

export 'lan_sync_platform_base.dart' show LanSyncPlatform, DiscoveredHost;
