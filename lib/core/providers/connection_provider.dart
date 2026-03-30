import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class AppConnectionState {
  final ConnectionStatus signalK;
  final String? signalKError;
  final ConnectionStatus lanSync;
  final String? lanSyncError;
  final List<String> connectedPeers; // IPs of connected LAN peers

  const AppConnectionState({
    this.signalK = ConnectionStatus.disconnected,
    this.signalKError,
    this.lanSync = ConnectionStatus.disconnected,
    this.lanSyncError,
    this.connectedPeers = const [],
  });

  AppConnectionState copyWith({
    ConnectionStatus? signalK,
    String? signalKError,
    ConnectionStatus? lanSync,
    String? lanSyncError,
    List<String>? connectedPeers,
  }) =>
      AppConnectionState(
        signalK: signalK ?? this.signalK,
        signalKError: signalKError ?? this.signalKError,
        lanSync: lanSync ?? this.lanSync,
        lanSyncError: lanSyncError ?? this.lanSyncError,
        connectedPeers: connectedPeers ?? this.connectedPeers,
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

  void addPeer(String ip) {
    if (!state.connectedPeers.contains(ip)) {
      state = state.copyWith(connectedPeers: [...state.connectedPeers, ip]);
    }
  }

  void removePeer(String ip) {
    state = state.copyWith(
      connectedPeers: state.connectedPeers.where((p) => p != ip).toList(),
    );
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, AppConnectionState>(
  ConnectionNotifier.new,
);
