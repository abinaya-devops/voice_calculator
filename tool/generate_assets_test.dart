// Generates binary assets for the app:
//   assets/logo/app_logo.png            (full launcher icon, 1024px)
//   assets/logo/app_logo_foreground.png (Android adaptive foreground, 1024px)
//   assets/sounds/key_press.wav         (key tap click)
//   assets/sounds/key_confirm.wav       (equals tone)
//
// Run with:  flutter test tool/generate_assets_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_calculator/widgets/app_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GENERATE ASSETS', () async {
    await _generateLogos();
    _generateSounds();
    expect(true, isTrue);
  });
}

Future<void> _generateLogos() async {
  Directory('assets/logo').createSync(recursive: true);

  // Full launcher icon (square, maskable).
  final full = await _renderLogo(size: 1024, rounded: false);
  File('assets/logo/app_logo.png').writeAsBytesSync(full);

  // Android adaptive foreground: artwork must sit inside the middle ~66%.
  final fg = await _renderLogo(size: 1024, rounded: false, inset: 0.36);
  File('assets/logo/app_logo_foreground.png').writeAsBytesSync(fg);

  // In-app showcase asset (rounded corners).
  final rounded = await _renderLogo(size: 512, rounded: true);
  File('assets/logo/app_logo_rounded.png').writeAsBytesSync(rounded);

  // ignore: avoid_print
  print('LOGOS WRITTEN');
}

Future<List<int>> _renderLogo({
  required int size,
  required bool rounded,
  double inset = 0,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  if (inset > 0) {
    // Paint the full-square logo into the central area.
    final inner = size * (1 - inset * 2);
    canvas.translate(size * inset, size * inset);
    canvas.scale(inner / 1024);
    AppLogoPainter(withBackground: true, rounded: rounded)
        .paint(canvas, const Size(1024, 1024));
  } else {
    AppLogoPainter(withBackground: true, rounded: rounded)
        .paint(canvas, Size(size.toDouble(), size.toDouble()));
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void _generateSounds() {
  Directory('assets/sounds').createSync(recursive: true);
  _writeWav('assets/sounds/key_press.wav', _keyPress());
  _writeWav('assets/sounds/key_confirm.wav', _keyConfirm());
  _writeWav('assets/sounds/key_clear.wav', _keyClear());
  // ignore: avoid_print
  print('SOUNDS WRITTEN');
}

// -----------------------------------------------------------------------------
// Procedural sound synthesis (44.1 kHz, 16-bit mono WAV)
// -----------------------------------------------------------------------------

const int _sampleRate = 44100;

/// Short "tick": filtered noise + tiny 1.9 kHz body. ~22 ms.
Float64List _keyPress() {
  const ms = 22;
  final n = _sampleRate * ms ~/ 1000;
  final out = Float64List(n);
  final rng = math.Random(7);
  var lp = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    final env = math.exp(-t * 260);
    final noise = (rng.nextDouble() * 2 - 1);
    lp += 0.35 * (noise - lp); // one-pole low-pass
    final body = math.sin(2 * math.pi * 1900 * t) * 0.5;
    out[i] = (lp * 0.75 + body * env * 0.4) * env;
  }
  return out;
}

/// "=" confirmation: warm two-note blip (E5 → A5). ~130 ms.
Float64List _keyConfirm() {
  const ms = 130;
  final n = _sampleRate * ms ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    const f1 = 659.25; // E5
    const f2 = 880.0; // A5
    final env1 = math.exp(-t * 28);
    final env2 =
        (t > 0.05) ? math.exp(-(t - 0.05) * 20) * (t > 0.05 ? 1 : 0) : 0.0;
    final wave =
        math.sin(2 * math.pi * f1 * t) * env1 * 0.5 +
            math.sin(2 * math.pi * f2 * t) * env2 * 0.45;
    out[i] = wave;
  }
  return out;
}

/// Clear: quick downward sweep. ~110 ms.
Float64List _keyClear() {
  const ms = 110;
  final n = _sampleRate * ms ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    final f = 900 - 500 * (t / 0.11);
    final env = math.exp(-t * 26);
    out[i] = math.sin(2 * math.pi * f * t) * env * 0.5;
  }
  return out;
}

void _writeWav(String path, Float64List samples) {
  final pcm = _toPcm16(samples);
  final bytes = BytesBuilder();
  final dataLen = pcm.length;
  const header = <int>[
    // RIFF chunk
    0x52, 0x49, 0x46, 0x46, // "RIFF"
    0, 0, 0, 0, // size filled below
    0x57, 0x41, 0x56, 0x45, // "WAVE"
    // fmt chunk
    0x66, 0x6D, 0x74, 0x20, // "fmt "
    16, 0, 0, 0, // chunk size
    1, 0, // PCM
    1, 0, // mono
    0x44, 0xAC, 0x00, 0x00, // 44100 Hz
    0x44, 0xAC, 0x00, 0x00, // byte rate
    2, 0, // block align (2 bytes/frame)
    16, 0, // bits per sample
    // data chunk
    0x64, 0x61, 0x74, 0x61, // "data"
    0, 0, 0, 0, // size filled below
  ];
  final h = Uint8List.fromList(header);
  void setLE32(int offset, int v) {
    h[offset] = v & 0xFF;
    h[offset + 1] = (v >> 8) & 0xFF;
    h[offset + 2] = (v >> 16) & 0xFF;
    h[offset + 3] = (v >> 24) & 0xFF;
  }

  setLE32(4, 36 + dataLen);
  setLE32(40, dataLen);
  bytes.add(h);
  bytes.add(pcm);
  File(path).writeAsBytesSync(bytes.toBytes());
}

Uint8List _toPcm16(Float64List samples) {
  final out = Uint8List(samples.length * 2);
  final bd = ByteData.view(out.buffer);
  for (var i = 0; i < samples.length; i++) {
    final v = samples[i].clamp(-1.0, 1.0);
    bd.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  return out;
}
