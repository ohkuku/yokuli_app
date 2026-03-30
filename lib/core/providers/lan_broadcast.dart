import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the LAN broadcast function registered by [LanSyncService] on start.
/// Module providers call this after local writes to broadcast changes to peers.
/// Null when LAN sync is not running or this device is not a host/client.
///
/// NOTE: upsertRemote() methods must NOT call this — only local mutations do.
final lanBroadcastProvider =
    StateProvider<void Function(Map<String, dynamic>)?>((_) => null);
