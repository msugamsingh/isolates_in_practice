// Generates the demo assets, so the repo needs no third-party media:
//
//   assets/sample_photo.jpg   a 4000x3000 generated "photo"
//   assets/lottie_bundle.zip  150 Lottie animations, each with many keyframes
//
// Run from the project root:  dart run tool/generate_assets.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

void main() {
  Directory('assets').createSync();
  _writePhoto();
  _writeLottieBundle();
}

void _writePhoto() {
  final photo = img.Image(width: 4000, height: 3000);
  final random = Random(1);
  for (final p in photo) {
    final t = p.y / photo.height;
    final hills = sin(p.x / 420) * 0.08 + sin(p.x / 97) * 0.02;
    final ground = t > 0.62 + hills;
    final noise = random.nextInt(12);
    p
      ..r = ground ? 60 + noise : (90 + 120 * (1 - t)).round() + noise
      ..g = ground ? 110 + noise : (140 + 90 * (1 - t)).round() + noise
      ..b = ground ? 50 + noise : (200 + 50 * (1 - t)).round() + noise;
  }
  img.fillCircle(
    photo,
    x: 2900,
    y: 700,
    radius: 260,
    color: img.ColorRgb8(255, 236, 170),
  );
  File('assets/sample_photo.jpg')
      .writeAsBytesSync(img.encodeJpg(photo, quality: 90));
  stdout.writeln('assets/sample_photo.jpg');
}

void _writeLottieBundle() {
  final archive = Archive();
  for (var i = 0; i < 150; i++) {
    final json = utf8.encode(jsonEncode(_animation(i)));
    archive.addFile(
      ArchiveFile.bytes(
        'animations/anim_${i.toString().padLeft(3, '0')}.json',
        json,
      ),
    );
  }
  File('assets/lottie_bundle.zip')
      .writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  stdout.writeln('assets/lottie_bundle.zip');
}

/// A rounded square that wobbles along a path and spins.
/// 600 position keyframes make each file large, like real exported art.
Map<String, Object> _animation(int index) {
  const frames = 600;
  final random = Random(index);
  final hue = index * 7.3;
  final color = _rgb(hue);
  final rx = 30 + random.nextInt(30);
  final ry = 30 + random.nextInt(30);
  final position = [
    for (var f = 0; f < frames; f++)
      {
        't': f,
        's': [
          100 + rx * sin(2 * pi * f / frames * 3) + random.nextDouble() * 2,
          100 + ry * cos(2 * pi * f / frames * 2) + random.nextDouble() * 2,
          0,
        ],
        'i': {'x': 0.5, 'y': 1},
        'o': {'x': 0.5, 'y': 0},
      },
  ];
  Map<String, Object> value(Object k) => {'a': 0, 'k': k};
  return {
    'v': '5.7.4',
    'nm': 'Sticker ${(index + 1).toString().padLeft(3, '0')}',
    'fr': 60,
    'ip': 0,
    'op': frames,
    'w': 200,
    'h': 200,
    'ddd': 0,
    'assets': <Object>[],
    'layers': [
      {
        'ddd': 0,
        'ind': 1,
        'ty': 4,
        'nm': 'shape',
        'sr': 1,
        'ks': {
          'o': value(100),
          'r': {
            'a': 1,
            'k': [
              {
                't': 0,
                's': [0],
                'i': {
                  'x': [0.5],
                  'y': [1],
                },
                'o': {
                  'x': [0.5],
                  'y': [0],
                },
              },
              {
                't': frames,
                's': [720],
              },
            ],
          },
          'p': {'a': 1, 'k': position},
          'a': value([0, 0, 0]),
          's': value([100, 100, 100]),
        },
        'ao': 0,
        'shapes': [
          {
            'ty': 'gr',
            'nm': 'box',
            'it': [
              {
                'ty': 'rc',
                'd': 1,
                's': value([70, 70]),
                'p': value([0, 0]),
                'r': value(16),
              },
              {
                'ty': 'fl',
                'c': value([...color, 1]),
                'o': value(100),
                'r': 1,
              },
              {
                'ty': 'tr',
                'p': value([0, 0]),
                'a': value([0, 0]),
                's': value([100, 100]),
                'r': value(0),
                'o': value(100),
              },
            ],
          },
        ],
        'ip': 0,
        'op': frames,
        'st': 0,
        'bm': 0,
      },
    ],
  };
}

List<double> _rgb(double hue) {
  final h = hue % 360 / 60;
  final x = 1 - (h % 2 - 1).abs();
  final (r, g, b) = switch (h.floor()) {
    0 => (1.0, x, 0.0),
    1 => (x, 1.0, 0.0),
    2 => (0.0, 1.0, x),
    3 => (0.0, x, 1.0),
    4 => (x, 0.0, 1.0),
    _ => (1.0, 0.0, x),
  };
  return [r * 0.85, g * 0.85, b * 0.85];
}
