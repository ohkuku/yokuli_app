import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

/// Sentinel used by [AppConnectionState.copyWith] so callers can explicitly
/// pass `null` to CLEAR an error field (vs. omitting the argument to keep it).
const _keepValue = Object();

class AppConnectionState {
  final ConnectionStatus signalK;
  final String? signalKError;
  final ConnectionStatus lanSync;
  final String? lanSyncError;
  final int peerCount; // number of clients connected to this host

  const AppConnectionState({
    this.signalK = ConnectionStatus.disconnected,
    this.signalKError,
    this.lanSync = ConnectionStatus.disconnected,
    this.lanSyncError,
    this.peerCount = 0,
  });

  /// [signalKError] / [lanSyncError]: omit → keep existing; pass `null` → clear.
  AppConnectionState copyWith({
    ConnectionStatus? signalK,
    Object? signalKError = _keepValue,
    ConnectionStatus? lanSync,
    Object? lanSyncError = _keepValue,
    int? peerCount,
  }) =>
      AppConnectionState(
        signalK: signalK ?? this.signalK,
        signalKError: identical(signalKError, _keepValue)
            ? this.signalKError
            : signalKError as String?,
        lanSync: lanSync ?? this.lanSync,
        lanSyncError: identical(lanSyncError, _keepValue)
            ? this.lanSyncError
            : lanSyncError as String?,
        peerCount: peerCount ?? this.peerCount,
      );

  bool get isSignalKConnected => signalK == ConnectionStatus.connected;
  bool get isLanSyncActive => lanSync == ConnectionStatus.connected;
}

class ConnectionNotifier extends Notifier<AppConnectionState> {
  @override
  AppConnectionState build() => const AppConnectionState();

  void setSignalKStatus(ConnectionStatus status, {String? error}) {
    // Automatically clear any previous error when leaving the error state.
    final clearError = status != ConnectionStatus.error;
    state = state.copyWith(
      signalK: status,
      signalKError: clearError ? null : error,
    );
  }

  void setLanSyncStatus(ConnectionStatus status, {String? error}) {
    final clearError = status != ConnectionStatus.error;
    state = state.copyWith(
      lanSync: status,
      lanSyncError: clearError ? null : error,
    );
  }

  void setPeerCount(int count) {
    state = state.copyWith(peerCount: count);
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, AppConnectionState>(
  ConnectionNotifier.new,
);
