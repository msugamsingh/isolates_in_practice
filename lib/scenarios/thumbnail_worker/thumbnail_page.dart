import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../common/scenario_page.dart';
import 'thumbnail_worker.dart';

/// Scenario: a photo gallery that makes thumbnails while you scroll.
///
/// API: a long-lived isolate (`Isolate.spawn` + `SendPort`/`ReceivePort`),
/// started once in `initState` and killed in `dispose`.
class ThumbnailPage extends StatefulWidget {
  const ThumbnailPage({super.key});

  @override
  State<ThumbnailPage> createState() => _ThumbnailPageState();
}

class _ThumbnailPageState extends State<ThumbnailPage> {
  final _worker = ThumbnailWorker();
  late final Future<void> _started = _worker.start();

  @override
  void dispose() {
    _worker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioPage(
      title: 'Gallery thumbnails',
      api: 'Long-lived isolate',
      description:
          'One worker isolate, started when this page opens, makes every '
          'thumbnail and caches it. Scroll fast: tiles fill in as the worker '
          'catches up, and the list never stutters. Scroll back up: cached '
          'tiles come back almost instantly.',
      busy: false,
      status:
          'Each tile sends (id, index) to the worker and gets '
          '(id, jpeg) back.',
      result: FutureBuilder<void>(
        future: _started,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Text('Starting worker...');
          }
          return SizedBox(
            height: 480,
            child: GridView.builder(
              itemCount: 300,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemBuilder: (context, i) => _Tile(worker: _worker, index: i),
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({required this.worker, required this.index});

  final ThumbnailWorker worker;
  final int index;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  // Ask once per tile; the Future survives rebuilds.
  late final Future<Uint8List> _jpeg = widget.worker.thumbnail(widget.index);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _jpeg,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(child: Text('${widget.index}')),
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}
