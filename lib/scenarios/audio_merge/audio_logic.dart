import 'dart:isolate';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// All audio here is 16-bit PCM WAV, stereo, 44.1 kHz.
const sampleRate = 44100;
const channels = 2;

class MergeJob {
  const MergeJob({
    required this.clipPaths,
    required this.outputPath,
    this.crossfade = const Duration(milliseconds: 500),
    this.musicVolume = 0.25,
  });

  /// Voice clips to join, in order. Paths, not bytes: Strings are free to
  /// send, and the isolate reads the files itself.
  final List<String> clipPaths;
  final String outputPath;
  final Duration crossfade;

  /// Background music level, 0 to 1.
  final double musicVolume;
}

class MergeResult {
  const MergeResult(this.path, this.duration, this.peaks, this.bytes);
  final String path;
  final Duration duration;

  /// A small summary for drawing a waveform (one value per bar, 0 to 1).
  /// Send back a summary, not millions of samples.
  final Float32List peaks;
  final int bytes;
}

/// Joins voice clips with crossfades, mixes in background music, normalises
/// the volume and writes one WAV file. Runs in `Isolate.run`.
MergeResult mergeClips(MergeJob job) {
  final clips = [for (final path in job.clipPaths) readWav(path)];
  final fade = job.crossfade.inMilliseconds * sampleRate ~/ 1000 * channels;

  // 1. Join clips; each new clip fades in while the previous one fades out.
  var length = clips.first.length;
  for (final clip in clips.skip(1)) {
    length += clip.length - fade;
  }
  final mix = Float32List(length);
  var start = 0;
  for (final clip in clips) {
    for (var i = 0; i < clip.length; i++) {
      var gain = 1.0;
      if (start > 0 && i < fade) gain = i / fade; // fade in
      if (i > clip.length - fade) gain = (clip.length - i) / fade; // fade out
      mix[start + i] += clip[i] * gain;
    }
    start += clip.length - fade;
  }

  // 2. Mix in background music (generated here; a real app would decode
  //    a bundled track or a file the user picked).
  for (var i = 0; i < mix.length; i += channels) {
    final t = (i ~/ channels) / sampleRate;
    final music = _pad(t) * job.musicVolume;
    mix[i] += music;
    mix[i + 1] += music;
  }

  // 3. Normalise: scale so the loudest sample sits just under full volume.
  var peak = 0.0;
  for (final s in mix) {
    peak = max(peak, s.abs());
  }
  final scale = peak == 0 ? 1.0 : 0.89 / peak; // about -1 dBFS
  for (var i = 0; i < mix.length; i++) {
    mix[i] *= scale;
  }

  final bytes = writeWav(job.outputPath, mix);
  return MergeResult(
    job.outputPath,
    Duration(milliseconds: mix.length ~/ channels * 1000 ~/ sampleRate),
    _peaks(mix, 120),
    bytes,
  );
}

/// Creates [count] voice-like test clips so the demo needs no recordings.
/// In a real app these would come from the microphone. Returns their paths.
List<String> writeTestClips(String directory, int count, Duration each) {
  final random = Random(3);
  return [
    for (var c = 0; c < count; c++)
      () {
        final frames = each.inMilliseconds * sampleRate ~/ 1000;
        final samples = Float32List(frames * channels);
        final base = 140.0 + random.nextInt(120);
        for (var f = 0; f < frames; f++) {
          final t = f / sampleRate;
          // A buzzy tone that rises and falls in "syllables".
          final syllable = max(0.0, sin(2 * pi * 3.2 * t));
          final v =
              syllable *
              0.5 *
              (sin(2 * pi * base * t) + 0.4 * sin(2 * pi * base * 2.01 * t));
          samples[f * 2] = v;
          samples[f * 2 + 1] = v;
        }
        final path = '$directory/clip_${c + 1}.wav';
        writeWav(path, samples);
        return path;
      }(),
  ];
}

double _pad(double t) =>
    0.3 * sin(2 * pi * 110 * t) +
    0.2 * sin(2 * pi * 164.81 * t) +
    0.2 * sin(2 * pi * 220 * t);

Float32List _peaks(Float32List samples, int bars) {
  final peaks = Float32List(bars);
  final per = samples.length ~/ bars;
  for (var b = 0; b < bars; b++) {
    var p = 0.0;
    for (var i = b * per; i < (b + 1) * per; i++) {
      p = max(p, samples[i].abs());
    }
    peaks[b] = p;
  }
  return peaks;
}

/// Reads a 16-bit PCM WAV into interleaved samples between -1 and 1.
/// Keeps it simple: expects the plain 44-byte header this file writes.
Float32List readWav(String path) {
  final data = ByteData.sublistView(File(path).readAsBytesSync());
  final count = (data.lengthInBytes - 44) ~/ 2;
  final samples = Float32List(count);
  for (var i = 0; i < count; i++) {
    samples[i] = data.getInt16(44 + i * 2, Endian.little) / 32768;
  }
  return samples;
}

/// Writes interleaved samples as a 16-bit PCM WAV. Returns the file size.
int writeWav(String path, Float32List samples) {
  final dataBytes = samples.length * 2;
  final out = ByteData(44 + dataBytes);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // fmt chunk size
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, channels, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * channels * 2, Endian.little); // byte rate
  out.setUint16(32, channels * 2, Endian.little); // block align
  out.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  out.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final s = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    out.setInt16(44 + i * 2, s, Endian.little);
  }
  File(path).writeAsBytesSync(out.buffer.asUint8List());
  return out.lengthInBytes;
}

// Why a top-level helper instead of calling Isolate.run in the widget?
// A closure can capture more than the variables it uses: the Dart VM keeps
// the whole surrounding context. A closure created inside a State method can
// end up holding `this`, and with it the widget tree, which cannot be sent
// (we hit exactly this: "Illegal argument in isolate message"). A closure
// created here can only see this function's parameters.
Future<MergeResult> mergeClipsInBackground(MergeJob job) =>
    Isolate.run(() => mergeClips(job));

Future<List<String>> writeTestClipsInBackground(
  String directory,
  int count,
  Duration each,
) => Isolate.run(() => writeTestClips(directory, count, each));
