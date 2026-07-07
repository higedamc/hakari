import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/data/signer/bech32.dart';

void main() {
  // Official NIP-19 test vector (from the NIP-19 spec):
  // 3bf0c63f... <-> npub180cvv07...
  const nip19Hex =
      '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
  const nip19Npub =
      'npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6';

  // Second vector: this npub is checksum-valid; its true payload was
  // derived by running the (spec-vector-verified) algorithm itself.
  // Note: the task brief suggested a different hex tail
  // (...8fd706714ddb9baf17feee351db97dbd) for this npub, but that pair
  // does NOT round-trip; the hex below is the actual decoded payload.
  const snowHex =
      '84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240';
  const snowNpub =
      'npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9';

  group('decodeNpub', () {
    test('decodes the official NIP-19 spec vector', () {
      expect(decodeNpub(nip19Npub), nip19Hex);
    });

    test('decodes npub1sn0wden... vector', () {
      expect(decodeNpub(snowNpub), snowHex);
    });

    test('accepts uppercase input (single-case)', () {
      expect(decodeNpub(nip19Npub.toUpperCase()), nip19Hex);
    });

    test('rejects mixed-case input', () {
      final mixed = 'Npub${nip19Npub.substring(4)}';
      expect(() => decodeNpub(mixed), throwsFormatException);
    });

    test('rejects corrupted checksum', () {
      // Flip the final character to another charset character.
      final last = nip19Npub[nip19Npub.length - 1];
      final swapped = last == 'q' ? 'p' : 'q';
      final corrupted = nip19Npub.substring(0, nip19Npub.length - 1) + swapped;
      expect(() => decodeNpub(corrupted), throwsFormatException);
    });

    test('rejects corrupted data character', () {
      final corrupted = nip19Npub.replaceRange(20, 21, 'x');
      expect(() => decodeNpub(corrupted), throwsFormatException);
    });

    test('rejects invalid (non-charset) character', () {
      final invalid = nip19Npub.replaceRange(20, 21, 'b');
      expect(() => decodeNpub(invalid), throwsFormatException);
    });

    test('rejects wrong hrp (nsec, valid checksum)', () {
      // Re-encode the same payload under "nsec": checksum is valid, hrp is
      // not "npub".
      final decoded = bech32Decode(nip19Npub);
      final nsec = bech32Encode('nsec', decoded.data);
      expect(() => decodeNpub(nsec), throwsFormatException);
    });

    test('rejects missing separator / empty hrp', () {
      expect(() => decodeNpub('npubqqqqqq'), throwsFormatException);
      expect(() => decodeNpub('1qqqqqqqqq'), throwsFormatException);
    });

    test('rejects too-short data part', () {
      expect(() => decodeNpub('npub1qqqq'), throwsFormatException);
    });

    test('rejects payload that is not 32 bytes', () {
      // 16-byte payload under npub: valid bech32, wrong length.
      final short = bech32Encode(
        'npub',
        convertBits(List<int>.filled(16, 0xab), 8, 5, pad: true),
      );
      expect(() => decodeNpub(short), throwsFormatException);
    });
  });

  group('encodeNpub', () {
    test('encodes the official NIP-19 spec vector', () {
      expect(encodeNpub(nip19Hex), nip19Npub);
    });

    test('encodes npub1sn0wden... vector', () {
      expect(encodeNpub(snowHex), snowNpub);
    });

    test('accepts uppercase hex', () {
      expect(encodeNpub(nip19Hex.toUpperCase()), nip19Npub);
    });

    test('rejects non-hex input', () {
      expect(() => encodeNpub('z' * 64), throwsFormatException);
    });

    test('rejects wrong-length hex', () {
      expect(
        () => encodeNpub(nip19Hex.substring(0, 62)),
        throwsFormatException,
      );
      expect(() => encodeNpub('${nip19Hex}ab'), throwsFormatException);
      expect(() => encodeNpub(''), throwsFormatException);
    });
  });

  group('round trips', () {
    test('hex -> npub -> hex', () {
      for (final hex in [
        nip19Hex,
        snowHex,
        '0' * 64,
        'f' * 64,
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      ]) {
        expect(decodeNpub(encodeNpub(hex)), hex.toLowerCase());
      }
    });

    test('npub -> hex -> npub', () {
      for (final npub in [nip19Npub, snowNpub]) {
        expect(encodeNpub(decodeNpub(npub)), npub);
      }
    });
  });

  group('convertBits', () {
    test('8->5->8 round trip', () {
      final bytes = List<int>.generate(32, (i) => (i * 7 + 3) & 0xff);
      final words = convertBits(bytes, 8, 5, pad: true);
      expect(convertBits(words, 5, 8, pad: false), bytes);
    });

    test('rejects out-of-range values', () {
      expect(() => convertBits([256], 8, 5, pad: true), throwsFormatException);
      expect(() => convertBits([32], 5, 8, pad: false), throwsFormatException);
      expect(() => convertBits([-1], 8, 5, pad: true), throwsFormatException);
    });

    test('rejects non-zero padding when pad is false', () {
      // A single 5-bit word cannot form a full byte; with a non-zero
      // value the leftover bits are not valid zero padding.
      expect(() => convertBits([31], 5, 8, pad: false), throwsFormatException);
    });
  });

  group('bech32Decode / bech32Encode (generic)', () {
    test('BIP-173 valid checksum vector', () {
      // From BIP-173 valid test vectors.
      final decoded = bech32Decode('a12uel5l');
      expect(decoded.hrp, 'a');
      expect(decoded.data, isEmpty);
      expect(bech32Encode('a', const []), 'a12uel5l');
    });

    test('rejects overlong input', () {
      final long =
          'an84characterslonghumanreadablepartthatcontains'
          'thenumber1andtheexcludedcharactersbio1569pvx';
      expect(() => bech32Decode(long), throwsFormatException);
    });
  });
}
