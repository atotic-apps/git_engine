import 'dart:convert';
import 'dart:typed_data';

/// One regular file of an uncompressed tar archive.
final class ArchiveFileEntry {
  /// Path recorded in the archive.
  final String name;

  /// Bytes of the file.
  final Uint8List content;

  const ArchiveFileEntry({required this.name, required this.content});

  /// Content decoded as UTF-8.
  String get text => utf8.decode(content);
}

/// Regular-file entries of an uncompressed tar archive, in archive order.
///
/// Enough of the format for the archives the tests read: 512-byte headers,
/// octal sizes, an optional `ustar` prefix, and metadata records skipped.
List<ArchiveFileEntry> readTarEntries(Uint8List bytes) {
  final List<ArchiveFileEntry> entries = <ArchiveFileEntry>[];
  var offset = 0;
  while (offset + 512 <= bytes.length) {
    final Uint8List header = bytes.sublist(offset, offset + 512);
    final String name = _tarString(header, 0, 100);
    if (name.isEmpty) {
      break;
    }
    final int size = _tarOctal(header, 124, 12);
    final String type = _tarString(header, 156, 1);
    final String prefix = _tarString(header, 345, 155);
    final int contentStart = offset + 512;
    if (type == '0' || type == '\x00') {
      entries.add(ArchiveFileEntry(
        name: prefix.isEmpty ? name : '$prefix/$name',
        content:
            Uint8List.sublistView(bytes, contentStart, contentStart + size),
      ));
    }
    offset = contentStart + ((size + 511) ~/ 512) * 512;
  }
  return entries;
}

/// Names of the entries of a zip archive, in central-directory order.
List<String> readZipNames(Uint8List bytes) {
  final int end = _findEndOfCentralDirectory(bytes);
  if (end < 0) {
    throw const FormatException('zip archive without an end record');
  }
  final int count = _uint16(bytes, end + 10);
  final int start = _uint32(bytes, end + 16);
  final List<String> names = <String>[];
  var offset = start;
  for (var index = 0; index < count; index++) {
    if (_uint32(bytes, offset) != 0x02014b50) {
      throw const FormatException('malformed zip central directory');
    }
    final int nameLength = _uint16(bytes, offset + 28);
    final int extraLength = _uint16(bytes, offset + 30);
    final int commentLength = _uint16(bytes, offset + 32);
    final int nameStart = offset + 46;
    names.add(utf8.decode(
      bytes.sublist(nameStart, nameStart + nameLength),
      allowMalformed: true,
    ));
    offset = nameStart + nameLength + extraLength + commentLength;
  }
  return names;
}

/// Offset of the end-of-central-directory record, or -1 when absent.
int _findEndOfCentralDirectory(Uint8List bytes) {
  final int lowest = bytes.length - 65557;
  for (var offset = bytes.length - 22;
      offset >= (lowest < 0 ? 0 : lowest);
      offset--) {
    if (_uint32(bytes, offset) == 0x06054b50) {
      return offset;
    }
  }
  return -1;
}

int _uint16(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _uint32(Uint8List bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

String _tarString(Uint8List header, int start, int length) {
  final List<int> slice =
      header.sublist(start, start + length).takeWhile((int byte) {
    return byte != 0;
  }).toList();
  return utf8.decode(slice, allowMalformed: true);
}

int _tarOctal(Uint8List header, int start, int length) {
  final String text = _tarString(header, start, length).trim();
  return text.isEmpty ? 0 : int.parse(text, radix: 8);
}
