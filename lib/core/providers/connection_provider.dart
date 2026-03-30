import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

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

  AppConnectionState copyWith({
    ConnectionStatus? signalK,
    String? signalKError,
    ConnectionStatus? lanSync,
    String? lanSyncError,
    int? peerCount,
  }) =>
      AppConnectionState(
        signalK: signalK ?? this.signalK,
        signalKError: signalKError ?? this.signalKError,
        lanSync: lanSync ?? this.lanSync,
        lanSyncError: lanSyncError ?? this.lanSyncError,
        peerCount: peerCount ?? this.peerCount,
      );

  bool get isSignalKConnected => signalK == ConnectionStatus.connected;
  bool get isLanSyncActive => lanSync == ConnectionStatus.connected;
}

class ConnectionNotifier extends Notifier<AppConnectionState> {
  @override
  AppConnectionState build() => const AppConnectionState();

  void setSignalKStatus(ConnectionStatus status, {String? error}) {
    state = state.copyWith(signalK: status, signalKError: error);
  }

  void setLanSyncStatus(ConnectionStatus status, {String? error}) {
    state = state.copyWith(lanSync: status, lanSyncError: error);
  }

  void setPeerCount(int count) {
    state = state.copyWith(peerCount: count);
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, AppConnectionState>(
  ConnectionNotifier.new,
);
