import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../common/scenario_page.dart';
import 'lottie_logic.dart';

/// Scenario: an app ships many animations in one zipped bundle (stickers,
/// onboarding, reactions) and unpacks it at startup.
///
/// API: `Isolate.run`. One job, one result.
class LottiePage extends StatefulWidget {
  const LottiePage({super.key});

  @override
  State<LottiePage> createState() => _LottiePageState();
}

class _LottiePageState extends State<LottiePage> {
  List<LottieClip> _clips = const [];
  bool _busy = false;
  String _status = 'assets/lottie_bundle.zip holds 150 animations.';

  Future<void> _unpack({required bool inIsolate}) async {
    setState(() {
      _busy = true;
      _clips = const [];
      _status = 'Unpacking...';
    });
    // Assets load on the main isolate (rootBundle is main-isolate only).
    // The load itself is async I/O and does not block the UI.
    final data = await rootBundle.load('assets/lottie_bundle.zip');
    final zip = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    final (clips, took) = await timed(() async {
      if (inIsolate) return unpackLottieBundleInBackground(zip);
      return unpackLottieBundle(zip);
    });
    if (!mounted) return;
    final total = clips.fold<int>(0, (sum, c) => sum + c.json.length);
    setState(() {
      _clips = clips;
      _busy = false;
      _status =
          '${inIsolate ? 'Isolate.run' : 'Main isolate'}: '
          '${clips.length} animations, ${formatBytes(total)} of JSON, '
          'unpacked in ${took.inMilliseconds} ms.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioPage(
      title: 'Lottie bundle',
      api: 'Isolate.run()',
      description:
          'Unzip a bundle of animations and validate each one. Unzipping and '
          'decoding JSON is Dart work, so the isolate keeps the screen moving.',
      busy: _busy,
      status: _status,
      onRunOnMain: () => _unpack(inIsolate: false),
      onRunInIsolate: () => _unpack(inIsolate: true),
      result: _clips.isEmpty
          ? null
          : SizedBox(
              height: 520,
              // A lazy grid: each animation is parsed (on the main isolate,
              // by package:lottie) only when its tile scrolls into view.
              child: GridView.builder(
                itemCount: _clips.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (context, i) => Card(
                  child: Tooltip(
                    message:
                        '${_clips[i].name}, ${_clips[i].duration.inSeconds}s',
                    child: Lottie.memory(_clips[i].json),
                  ),
                ),
              ),
            ),
    );
  }
}
