import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class QishuiDecrypt {
  static final _cipher = AesCtr.with128bits(macAlgorithm: MacAlgorithm.empty);

  static int _bitcount(int n) {
    var u = n.toUnsigned(32);
    u = u - ((u >> 1) & 0x55555555);
    u = (u & 0x33333333) + ((u >> 2) & 0x33333333);
    return (((u + (u >> 4)) & 0x0F0F0F0F) * 0x01010101 >> 24) & 0xFF;
  }

  static int _decodeBase36(int c) {
    final char = String.fromCharCode(c).toLowerCase();
    if (char.compareTo('0') >= 0 && char.compareTo('9') <= 0) return c - 48;
    if (char.compareTo('a') >= 0 && char.compareTo('z') <= 0) return c - 97 + 10;
    return 0xFF;
  }

  static Uint8List _decryptSpadeInner(Uint8List keyBytes) {
    final result = Uint8List(keyBytes.length);
    final buff = Uint8List.fromList([0xFA, 0x55, ...keyBytes]);
    for (var i = 0; i < keyBytes.length; i++) {
      var v = (keyBytes[i] ^ buff[i]) - _bitcount(i) - 21;
      while (v < 0) {
        v += 255;
      }
      result[i] = v % 256;
    }
    return result;
  }

  static String? extractKey(String playAuth) {
    try {
      final bytesData = base64Decode(playAuth);
      if (bytesData.length < 3) return null;

      final paddingLen = (bytesData[0] ^ bytesData[1] ^ bytesData[2]) - 48;
      if (bytesData.length < paddingLen + 2) return null;

      final innerInput = bytesData.sublist(1, bytesData.length - paddingLen);
      final tmpBuff = _decryptSpadeInner(innerInput);

      final skipBytes = _decodeBase36(tmpBuff[0]);
      final endIndex = 1 + (bytesData.length - paddingLen - 2) - skipBytes;

      if (endIndex > tmpBuff.length || endIndex < 1) return null;

      return utf8.decode(tmpBuff.sublist(1, endIndex));
    } catch (e) {
      return null;
    }
  }

  static _Box? _findBox(Uint8List data, String boxType, int start, int end) {
    var pos = start;
    final view = ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    
    while (pos + 8 <= end) {
      final size = view.getUint32(pos);
      if (size < 8) break;
      
      final type = String.fromCharCodes(data.sublist(pos + 4, pos + 8));
      if (type == boxType) {
        return _Box(pos, size, data.sublist(pos + 8, pos + size));
      }
      pos += size;
    }
    return null;
  }

  static List<int> _parseStsz(Uint8List data) {
    if (data.length < 12) return [];
    final view = ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    final sampleSizeFixed = view.getUint32(4);
    final sampleCount = view.getUint32(8);
    
    if (sampleSizeFixed != 0) {
      return List.filled(sampleCount, sampleSizeFixed);
    } else {
      final sizes = <int>[];
      for (var i = 0; i < sampleCount; i++) {
        sizes.add(view.getUint32(12 + i * 4));
      }
      return sizes;
    }
  }

  static List<Uint8List> _parseSenc(Uint8List data) {
    if (data.length < 8) return [];
    final view = ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    final flags = view.getUint32(0) & 0x00FFFFFF;
    final sampleCount = view.getUint32(4);
    final ivs = <Uint8List>[];
    var ptr = 8;
    final hasSubsamples = (flags & 0x02) != 0;
    
    for (var i = 0; i < sampleCount; i++) {
      ivs.add(data.sublist(ptr, ptr + 8));
      ptr += 8;
      if (hasSubsamples) {
        final subCount = view.getUint16(ptr);
        ptr += 2 + (subCount * 6);
      }
    }
    return ivs;
  }

  static Future<Uint8List> decryptAudio(Uint8List fileData, String spadeA) async {
    final hexKey = extractKey(spadeA);
    if (hexKey == null) throw Exception("Could not extract key");

    final keyBytes = Uint8List.fromList(
      Iterable.generate(hexKey.length ~/ 2, (i) => int.parse(hexKey.substring(i * 2, i * 2 + 2), radix: 16)).toList()
    );
    
    final secretKey = SecretKey(keyBytes);

    final moov = _findBox(fileData, "moov", 0, fileData.length);
    if (moov == null) throw Exception("moov not found");

    _Box? stbl = _findBox(fileData, "stbl", moov.offset, moov.offset + moov.size);
    if (stbl == null) {
      final trak = _findBox(fileData, "trak", moov.offset + 8, moov.offset + moov.size);
      if (trak != null) {
        final mdia = _findBox(fileData, "mdia", trak.offset + 8, trak.offset + trak.size);
        if (mdia != null) {
          final minf = _findBox(fileData, "minf", mdia.offset + 8, mdia.offset + mdia.size);
          if (minf != null) {
            stbl = _findBox(fileData, "stbl", minf.offset + 8, minf.offset + minf.size);
          }
        }
      }
    }
    if (stbl == null) throw Exception("stbl not found");

    final stszBox = _findBox(fileData, "stsz", stbl.offset + 8, stbl.offset + stbl.size);
    if (stszBox == null) throw Exception("stsz not found");
    final sampleSizes = _parseStsz(stszBox.data);

    _Box? sencBox = _findBox(fileData, "senc", moov.offset + 8, moov.offset + moov.size);
    if (sencBox == null) sencBox = _findBox(fileData, "senc", stbl.offset + 8, stbl.offset + stbl.size);
    if (sencBox == null) throw Exception("senc not found");
    final ivs = _parseSenc(sencBox.data);

    final mdat = _findBox(fileData, "mdat", 0, fileData.length);
    if (mdat == null) throw Exception("mdat not found");

    final result = Uint8List.fromList(fileData);
    var readPtr = mdat.offset + 8;
    final decryptedMdat = <Uint8List>[];

    for (var i = 0; i < sampleSizes.length; i++) {
      final size = sampleSizes[i];
      final chunk = fileData.sublist(readPtr, readPtr + size);
      
      if (i < ivs.length) {
        final ivShort = ivs[i];
        final iv = Uint8List(16);
        iv.setRange(0, 8, ivShort);
        
        final secretBox = SecretBox(chunk, nonce: iv, mac: Mac.empty);
        final decryptedChunk = await _cipher.decrypt(secretBox, secretKey: secretKey);
        decryptedMdat.add(Uint8List.fromList(decryptedChunk));
      } else {
        decryptedMdat.add(chunk);
      }
      readPtr += size;
    }

    var offset = mdat.offset + 8;
    for (final chunk in decryptedMdat) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    // Patch 'enca' to 'mp4a'
    final stsd = _findBox(fileData, "stsd", stbl.offset + 8, stbl.offset + stbl.size);
    if (stsd != null) {
      for (var i = 0; i < stsd.data.length - 4; i++) {
        if (stsd.data[i] == 101 && stsd.data[i+1] == 110 && stsd.data[i+2] == 99 && stsd.data[i+3] == 97) { // 'enca'
          result[stsd.offset + 8 + i] = 109; // 'm'
          result[stsd.offset + 8 + i + 1] = 112; // 'p'
          result[stsd.offset + 8 + i + 2] = 52; // '4'
          result[stsd.offset + 8 + i + 3] = 97; // 'a'
          break;
        }
      }
    }

    return result;
  }
}

class _Box {
  final int offset;
  final int size;
  final Uint8List data;
  _Box(this.offset, this.size, this.data);
}
