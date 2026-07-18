import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/data/signer/amber_signer_service.dart';
import 'package:hakari/domain/failures/failures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('jp.godzhigella.hakari/amber-test');
  const hexPubkey =
      '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';

  final calls = <MethodCall>[];
  Future<Object?> Function(MethodCall call)? handler;

  setUp(() {
    calls.clear();
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler!(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  AmberSignerService service({
    Future<String?> Function()? pubkeyHexProvider = _hexProvider,
    Duration timeout = const Duration(seconds: 5),
  }) => AmberSignerService(
    channel: channel,
    pubkeyHexProvider: pubkeyHexProvider,
    foregroundTimeout: timeout,
    isAndroidOverride: true,
  );

  group('ContentProvider-first signing', () {
    test('CP success returns silently without a foreground intent', () async {
      handler = (call) async {
        expect(call.method, 'signEventWithAmberContentProvider');
        final args = (call.arguments as Map).cast<String, String>();
        expect(args['event'], '{"kind":1351}');
        expect(args['npub'], startsWith('npub1'));
        return '{"signed":true}';
      };
      final signed = await service().signEvent('{"kind":1351}');
      expect(signed, '{"signed":true}');
      expect(calls, hasLength(1));
    });

    test(
      'CP denial (AMBER_ERROR) falls back to the foreground intent',
      () async {
        handler = (call) async {
          if (call.method == 'signEventWithAmberContentProvider') {
            throw PlatformException(
              code: 'AMBER_ERROR',
              message: 'No response from Amber ContentProvider',
            );
          }
          expect(call.method, 'signEventWithAmber');
          return '{"signed":"fg"}';
        };
        final signed = await service().signEvent('{"kind":1351}');
        expect(signed, '{"signed":"fg"}');
        expect(calls.map((c) => c.method), [
          'signEventWithAmberContentProvider',
          'signEventWithAmber',
        ]);
      },
    );

    test('CP rejection also falls back (no always-approve grant)', () async {
      handler = (call) async {
        if (call.method == 'nip44EncryptWithAmberContentProvider') {
          throw PlatformException(code: 'AMBER_REJECTED');
        }
        return 'ciphertext';
      };
      final out = await service().nip44Encrypt('secret', hexPubkey);
      expect(out, 'ciphertext');
      expect(calls.last.method, 'nip44EncryptWithAmber');
    });

    test('CP path is skipped entirely without a pubkey provider', () async {
      handler = (call) async {
        expect(call.method, 'signEventWithAmber');
        return 'signed';
      };
      final signed = await service(
        pubkeyHexProvider: null,
      ).signEvent('{"kind":1351}');
      expect(signed, 'signed');
      expect(calls, hasLength(1));
    });
  });

  group('foreground failures', () {
    test('AMBER_REJECTED on the foreground path propagates', () async {
      handler = (call) async {
        if (call.method.endsWith('ContentProvider')) {
          throw PlatformException(code: 'AMBER_ERROR');
        }
        throw PlatformException(code: 'AMBER_REJECTED');
      };
      await expectLater(
        service().signEvent('{"kind":1351}'),
        throwsA(isA<SignerRejectedFailure>()),
      );
    });

    test(
      'timeout surfaces SignerTimeoutFailure; late reply is harmless',
      () async {
        final late = Completer<Object?>();
        handler = (call) async {
          if (call.method.endsWith('ContentProvider')) {
            throw PlatformException(code: 'AMBER_ERROR');
          }
          return late.future;
        };
        await expectLater(
          service(
            timeout: const Duration(milliseconds: 50),
          ).signEvent('{"kind":1351}'),
          throwsA(isA<SignerTimeoutFailure>()),
        );
        // The late reply must not produce an unhandled error.
        late.complete('too-late');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
    );

    test('AMBER_NOT_INSTALLED aborts without a fallback attempt', () async {
      handler = (call) async {
        throw PlatformException(code: 'AMBER_NOT_INSTALLED');
      };
      await expectLater(
        service().nip44Decrypt('cipher', hexPubkey),
        throwsA(isA<SignerUnavailableFailure>()),
      );
      // Unavailability short-circuits: no foreground retry.
      expect(calls, hasLength(1));
    });
  });
}

Future<String?> _hexProvider() async =>
    '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
