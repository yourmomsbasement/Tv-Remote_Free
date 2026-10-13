import 'dart:convert';
import 'dart:typed_data';

/// Just enough Protocol Buffers to speak the Android TV Remote protocol:
/// varint and length-delimited fields, plus varint length-prefixed framing.
class ProtoWriter {
  final _bytes = BytesBuilder(copy: false);

  static void _writeVarint(BytesBuilder out, int value) {
    if (value < 0) throw ArgumentError.value(value, 'value', 'negative');
    while (value >= 0x80) {
      out.addByte((value & 0x7F) | 0x80);
      value >>= 7;
    }
    out.addByte(value);
  }

  void _tag(int field, int wireType) =>
      _writeVarint(_bytes, (field << 3) | wireType);

  void varint(int field, int value) {
    _tag(field, 0);
    _writeVarint(_bytes, value);
  }

  void boolean(int field, bool value) => varint(field, value ? 1 : 0);

  void bytes(int field, List<int> value) {
    _tag(field, 2);
    _writeVarint(_bytes, value.length);
    _bytes.add(value);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  void message(int field, ProtoWriter value) => bytes(field, value.toBytes());

  Uint8List toBytes() => _bytes.toBytes();

  /// The message prefixed with its varint length, as sent on the wire.
  Uint8List toFrame() {
    final body = toBytes();
    final out = BytesBuilder(copy: false);
    _writeVarint(out, body.length);
    out.add(body);
    return out.toBytes();
  }
}

/// A decoded message: field number → values in arrival order. Varints decode
/// to [int], length-delimited fields to [Uint8List].
class ProtoMessage {
  ProtoMessage._(this._fields);

  final Map<int, List<Object>> _fields;

  factory ProtoMessage.decode(List<int> data) {
    final fields = <int, List<Object>>{};
    final reader = _Reader(data);
    while (!reader.done) {
      final tag = reader.varint();
      final field = tag >> 3;
      final Object value = switch (tag & 7) {
        0 => reader.varint(),
        1 => reader.take(8),
        2 => reader.take(reader.varint()),
        5 => reader.take(4),
        final type => throw FormatException('Unsupported wire type $type'),
      };
      fields.putIfAbsent(field, () => []).add(value);
    }
    return ProtoMessage._(fields);
  }

  bool has(int field) => _fields.containsKey(field);

  int? integer(int field) {
    final v = _fields[field]?.last;
    return v is int ? v : null;
  }

  bool? boolean(int field) {
    final v = integer(field);
    return v == null ? null : v != 0;
  }

  Uint8List? bytes(int field) {
    final v = _fields[field]?.last;
    return v is Uint8List ? v : null;
  }

  String? string(int field) {
    final v = bytes(field);
    return v == null ? null : utf8.decode(v, allowMalformed: true);
  }

  ProtoMessage? message(int field) {
    final v = bytes(field);
    return v == null ? null : ProtoMessage.decode(v);
  }

  List<ProtoMessage> messages(int field) => [
    for (final v in _fields[field] ?? const <Object>[])
      if (v is Uint8List) ProtoMessage.decode(v),
  ];
}

class _Reader {
  _Reader(this._data);

  final List<int> _data;
  int _pos = 0;

  bool get done => _pos >= _data.length;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_pos >= _data.length) throw const FormatException('Truncated varint');
      final byte = _data[_pos++];
      result |= (byte & 0x7F) << shift;
      if (byte < 0x80) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('Varint too long');
    }
  }

  Uint8List take(int length) {
    if (_pos + length > _data.length) {
      throw const FormatException('Truncated field');
    }
    final out = Uint8List.fromList(_data.sublist(_pos, _pos + length));
    _pos += length;
    return out;
  }
}

/// Splits a byte stream into varint length-prefixed messages. Chunks may
/// split anywhere, including inside the length prefix.
class ProtoFrameDecoder {
  final _buffer = <int>[];

  /// Adds received bytes and returns every message completed by them.
  List<Uint8List> add(List<int> chunk) {
    _buffer.addAll(chunk);
    final frames = <Uint8List>[];
    while (true) {
      var length = 0;
      var shift = 0;
      var pos = 0;
      var complete = false;
      while (pos < _buffer.length) {
        final byte = _buffer[pos++];
        length |= (byte & 0x7F) << shift;
        if (byte < 0x80) {
          complete = true;
          break;
        }
        shift += 7;
        if (shift > 35) throw const FormatException('Bad frame length');
      }
      if (!complete || _buffer.length < pos + length) return frames;
      frames.add(Uint8List.fromList(_buffer.sublist(pos, pos + length)));
      _buffer.removeRange(0, pos + length);
    }
  }
}
