import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

/// Raised when Signal K has failed to connect [maxConsecutiveErrors] times in a
/// row.  The app should navigate the user back to the setup screen so they can
/// correct the server address / credentials.
enum SignalKFailureReason { none, addressUnreachable, authFailed }

/// Sentinel used by [AppConnectionState.copyWith] so callers can explicitly
/// pass `null` to CLEAR an error field (vs. omitting the argument to keep it).
const _keepValue = Object();

class AppConnectionState {
  final ConnectionStatus signalK;
  final String? signalKError;
  final ConnectionStatus lanSync;
  final String? lanSyncError;
  final int peerCount; // number of clients connected to this host

  /// Set to a non-[none] value when Signal K has failed persistently and the
  /// app should redirect the user back to the configuration screen.
  final SignalKFailureReason signalKPermanentFailure;

  const AppConnectionState({
    this.signalK = ConnectionStatus.disconnected,
    this.signalKError,
    this.lanSync = ConnectionStatus.disconnected,
    this.lanSyncError,
    this.peerCount = 0,
    this.signalKPermanentFailure = SignalKFailureReason.none,
  });

  /// [signalKError] / [lanSyncError]: omit → keep existing; pass `null` → clear.
  AppConnectionState copyWith({
    ConnectionStatus? signalK,
    Object? signalKError = _keepValue,
    ConnectionStatus? lanSync,
    Object? lanSyncError = _keepValue,
    int? peerCount,
    SignalKFailureReason? signalKPermanentFailure,
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
        signalKPermanentFailure:
            signalKPermanentFailure ?? this.signalKPermanentFailure,
      );

  bool get isSignalKConnected => signalK == ConnectionStatus.connected;
  bool get isLanSyncActive => lanSync == ConnectionStatus.connected;
  bool get hasSignalKPermanentFailure =>
      signalKPermanentFailure != SignalKFailureReason.none;
}

class ConnectionNotifier extends Notifier<AppConnectionState> {
  @override
  AppConnectionState build() => const AppConnectionState();

  void setSignalKStatus(ConnectionStatus status, {String? error}) {
    // Automatically clear any previous error when leaving the error state.
    final clearError = status != ConnectionStatus.error;
    // Clear permanent failure flag when we successfully connect.
    final clearPermanent = status == ConnectionStatus.connected;
    state = state.copyWith(
      signalK: status,
      signalKError: clearError ? null : error,
      signalKPermanentFailure: clearPermanent
          ? SignalKFailureReason.none
          : null, // null = keep existing value
    );
  }

  /// Called by [SignalKClient] after [maxConsecutiveErrors] consecutive failures.
  /// Triggers navigation back to the setup screen.
  void setSignalKPermanentFailure(SignalKFailureReason reason) {
    state = state.copyWith(
      signalK: ConnectionStatus.error,
      signalKPermanentFailure: reason,
    );
  }

  /// Reset the permanent failure flag — called when the user taps "Retry" or
  /// navigates back to setup and saves new credentials.
  void clearSignalKPermanentFailure() {
    state = state.copyWith(
      signalKPermanentFailure: SignalKFailureReason.none,
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
