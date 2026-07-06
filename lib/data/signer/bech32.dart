/// Minimal pure-Dart bech32 (BIP-173) codec, scoped to what hakari needs:
/// NIP-19 `npub` <-> 64-char hex pubkey conversion for Amber (NIP-55).
///
/// Implements the bech32 charset, polymod checksum (verify + create) and
/// 5-bit <-> 8-bit regrouping. No external dependencies.
///
/// All failures throw [FormatException] with a descriptive message.
library;

const String _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

const List<int> _generator = <int>[
  0x3b6a57b2,
  0x26508e6d,
  0x1ea119fa,
  0x3d4233dd,
  0x2a1462b3,
];

/// bech32 checksum polymod over 5-bit values.
int _polymod(List<int> values) {
  var chk = 1;
  for (final v in values) {
    final b = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (var i = 0; i < 5; i++) {
      if ((b >> i) & 1 != 0) {
        chk ^= _generator[i];
      }
    }
  }
  return chk;
}

/// Expand the human-readable part for checksum computation.
List<int> _hrpExpand(String hrp) {
  final codes = hrp.codeUnits;
  return <int>[
    for (final c in codes) c >> 5,
    0,
    for (final c in codes) c & 31,
  ];
}

bool _verifyChecksum(String hrp, List<int> data) {
  return _polymod(<int>[..._hrpExpand(hrp), ...data]) == 1;
}

List<int> _createChecksum(String hrp, List<int> data) {
  final values = <int>[..._hrpExpand(hrp), ...data, 0, 0, 0, 0, 0, 0];
  final pm = _polymod(values) ^ 1;
  return <int>[for (var i = 0; i < 6; i++) (pm >> (5 * (5 - i))) & 31];
}

/// Regroup [data] from [fromBits]-wide values to [toBits]-wide values.
///
/// With [pad] true (encoding, 8->5) a final partial group is zero-padded.
/// With [pad] false (decoding, 5->8) leftover bits must be zero padding of
/// fewer than [fromBits] bits, otherwise a [FormatException] is thrown.
List<int> convertBits(List<int> data, int fromBits, int toBits,
    {required bool pad}) {
  var acc = 0;
  var bits = 0;
  final result = <int>[];
  final maxV = (1 << toBits) - 1;
  for (final value in data) {
    if (value < 0 || (value >> fromBits) != 0) {
      throw FormatException('bech32: invalid value $value for $fromBits bits');
    }
    acc = (acc << fromBits) | value;
    bits += fromBits;
    while (bits >= toBits) {
      bits -= toBits;
      result.add((acc >> bits) & maxV);
    }
  }
  if (pad) {
    if (bits > 0) {
      result.add((acc << (toBits - bits)) & maxV);
    }
  } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxV) != 0) {
    throw const FormatException('bech32: invalid padding');
  }
  return result;
}

/// Decoded bech32 string: human-readable part + 5-bit data (checksum removed).
class Bech32Decoded {
  final String hrp;
  final List<int> data;
  const Bech32Decoded(this.hrp, this.data);
}

/// Strict bech32 decode: validates case, charset, structure and checksum.
/// Returns the HRP and the 5-bit data words (without the 6 checksum words).
Bech32Decoded bech32Decode(String input, {int maxLength = 90}) {
  if (input.length > maxLength) {
    throw FormatException('bech32: input longer than $maxLength chars');
  }
  final lower = input.toLowerCase();
  if (input != lower && input != input.toUpperCase()) {
    throw const FormatException('bech32: mixed-case string');
  }
  for (final c in lower.codeUnits) {
    if (c < 33 || c > 126) {
      throw const FormatException('bech32: character out of range');
    }
  }
  final sep = lower.lastIndexOf('1');
  if (sep < 1) {
    throw const FormatException('bech32: missing or empty human-readable part');
  }
  if (lower.length - sep - 1 < 6) {
    throw const FormatException('bech32: data part too short');
  }
  final hrp = lower.substring(0, sep);
  final data = <int>[];
  for (final c in lower.substring(sep + 1).split('')) {
    final idx = _charset.indexOf(c);
    if (idx == -1) {
      throw FormatException('bech32: invalid data character "$c"');
    }
    data.add(idx);
  }
  if (!_verifyChecksum(hrp, data)) {
    throw const FormatException('bech32: checksum verification failed');
  }
  return Bech32Decoded(hrp, data.sublist(0, data.length - 6));
}

/// bech32 encode [data] (5-bit words) under [hrp], appending the checksum.
String bech32Encode(String hrp, List<int> data) {
  final checksum = _createChecksum(hrp, data);
  final buf = StringBuffer(hrp)..write('1');
  for (final v in <int>[...data, ...checksum]) {
    buf.write(_charset[v]);
  }
  return buf.toString();
}

final RegExp _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

/// Decode a NIP-19 `npub1...` string to its 64-char lowercase hex pubkey.
/// Throws [FormatException] on bad HRP, checksum or payload length.
String decodeNpub(String npub) {
  final decoded = bech32Decode(npub);
  if (decoded.hrp != 'npub') {
    throw FormatException('bech32: expected hrp "npub", got "${decoded.hrp}"');
  }
  final bytes = convertBits(decoded.data, 5, 8, pad: false);
  if (bytes.length != 32) {
    throw FormatException(
        'bech32: npub payload must be 32 bytes, got ${bytes.length}');
  }
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

/// Encode a 64-char hex pubkey as a NIP-19 `npub1...` string (for display).
/// Throws [FormatException] if [hexPubkey] is not 64 hex chars.
String encodeNpub(String hexPubkey) {
  if (!_hex64.hasMatch(hexPubkey)) {
    throw const FormatException('bech32: pubkey must be 64 hex characters');
  }
  final bytes = <int>[
    for (var i = 0; i < 64; i += 2)
      int.parse(hexPubkey.substring(i, i + 2), radix: 16),
  ];
  return bech32Encode('npub', convertBits(bytes, 8, 5, pad: true));
}
