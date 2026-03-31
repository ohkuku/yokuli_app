import 'package:flutter_test/flutter_test.dart';
import 'package:yokuli_app/core/services/lan_sync/lan_sync_service.dart';

void main() {
  group('shouldAttemptPeerConnect', () {
    test('returns false for self peer', () {
      final ok = shouldAttemptPeerConnect(
        isSelf: true,
        isClientConnected: false,
        nowMs: 10_000,
        lastAttemptMs: 0,
      );
      expect(ok, isFalse);
    });

    test('returns false when already client-connected', () {
      final ok = shouldAttemptPeerConnect(
        isSelf: false,
        isClientConnected: true,
        nowMs: 10_000,
        lastAttemptMs: 0,
      );
      expect(ok, isFalse);
    });

    test('returns false within cooldown', () {
      final ok = shouldAttemptPeerConnect(
        isSelf: false,
        isClientConnected: false,
        nowMs: 10_000,
        lastAttemptMs: 9_000,
        cooldownMs: 5_000,
      );
      expect(ok, isFalse);
    });

    test('returns true when not connected and cooldown elapsed', () {
      final ok = shouldAttemptPeerConnect(
        isSelf: false,
        isClientConnected: false,
        nowMs: 10_000,
        lastAttemptMs: 0,
        cooldownMs: 5_000,
      );
      expect(ok, isTrue);
    });
  });
}

