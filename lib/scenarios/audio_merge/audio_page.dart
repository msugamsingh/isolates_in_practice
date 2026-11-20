import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../common/scenario_page.dart';
import 'audio_logic.dart';

/// Scenario: a voice-notes or podcast app joins recorded clips into one file
/// with background music.
///
/// API: `Isolate.run`. The isolate reads the clip files, does all the sample
/// maths, writes the result file, and returns only its path plus a small
/// waveform summary.
class AudioPage extends StatefulWidget {
  const AudioPage({super.key});

  @override
  State<AudioPage> createState() => _AudioPageState();
}

class _AudioPageState extends State<AudioPage> {
  List<String> _clips = const [];
  String _dir = '';
  MergeResult? _result;
  bool _busy = false;
  String _status = 'Preparing four 30-second test clips...';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() => _busy = true);
    // Plugins (path_provider) on the main isolate; send only the path.
    final dir = (await getTemporaryDirectory()).path;
    final clips = await writeTestClipsInBackground(
      dir,
      4,
      const Duration(seconds: 30),
    );
    if (!mounted) return;
    setState(() {
      _dir = dir;
      _clips = clips;
      _busy = false;
      _status = '${clips.length} clips ready (in a real app: recordings).';
    });
  }

  Future<void> _merge({required bool inIsolate}) async {
    final job = MergeJob(clipPaths: _clips, outputPath: '$_dir/merged.wav');
    setState(() {
      _busy = true;
      _status = 'Merging...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final (result, took) = await timed(() async {
      if (inIsolate) return mergeClipsInBackground(job);
      return mergeClips(job);
    });
    if (!mounted) return;
    setState(() {
      _result = result;
      _busy = false;
      _status =
          '${inIsolate ? 'Isolate.run' : 'Main isolate'}: '
          '${result.duration.inSeconds} s of audio, '
          '${formatBytes(result.bytes)} WAV, in ${took.inMilliseconds} ms.\n'
          '${result.path}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioPage(
      title: 'Merge audio clips',
      api: 'Isolate.run()',
      description:
          'Join recorded clips with crossfades, mix in background music, '
          'normalise the volume, and write one WAV file. Millions of samples '
          'go through Dart code, which is exactly the kind of work to move '
          'off the main isolate.',
      busy: _busy || _clips.isEmpty,
      status: _status,
      onRunOnMain: () => _merge(inIsolate: false),
      onRunInIsolate: () => _merge(inIsolate: true),
      result: _result == null
          ? null
          : SizedBox(
              height: 120,
              child: CustomPaint(
                painter: _WaveformPainter(
                  _result!.peaks,
                  Theme.of(context).colorScheme.primary,
                ),
                size: Size.infinite,
              ),
            ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(this.peaks, this.color);

  final Float32List peaks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final bar = size.width / peaks.length;
    for (var i = 0; i < peaks.length; i++) {
      final h = max(2.0, peaks[i] * size.height);
      canvas.drawRect(
        Rect.fromLTWH(i * bar, (size.height - h) / 2, bar * 0.7, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.peaks != peaks;
}
