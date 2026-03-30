import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class ConnectionState {
  final ConnectionStatus signalK;
  final String? signalKError;
  final ConnectionStatus lanSync;
  final String? lanSyncError;
  final List<String> connectedPeers; // IPs of connected LAN peers

  const ConnectionState({
    this.signalK = ConnectionStatus.disconnected,
    this.signalKError,
    this.lanSync = ConnectionStatus.disconnected,
    this.lanSyncError,
    this.connectedPeers = const [],
  });

  ConnectionState copyWith({
    ConnectionStatus? signalK,
    String? signalKError,
    ConnectionStatus? lanSync,
    String? lanSyncError,
    List<String>? connectedPeers,
  }) =>
      ConnectionState(
        signalK: signalK ?? this.signalK,
        signalKError: signalKError ?? this.signalKError,
        lanSync: lanSync ?? this.lanSync,
        lanSyncError: lanSyncError ?? this.lanSyncError,
        connectedPeers: connectedPeers ?? this.connectedPeers,
      );

  bool get isSignalKConnected => signalK == ConnectionStatus.connected;
  bool get isLanSyncActive => lanSync == ConnectionStatus.connected;
}

class ConnectionNotifier extends Notifier<ConnectionState> {
  @override
  ConnectionState build() => const ConnectionState();

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

final connectionProvider = NotifierProvider<ConnectionNotifier, ConnectionState>(
  ConnectionNotifier.new,
);
