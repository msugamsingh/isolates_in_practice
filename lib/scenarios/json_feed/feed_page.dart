import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../common/scenario_page.dart';
import 'feed_logic.dart';

/// Scenario: a large API response.
///
/// API: `compute`. It is Flutter's helper: one function, one argument.
/// On Android, iOS and desktop it is the same as `Isolate.run`. On the web
/// (no isolates) it runs on the main thread, so the code still works there.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  static const _postCount = 200000;

  String? _body;
  List<Post> _posts = const [];
  bool _busy = false;
  String _status = 'Preparing a fake API response...';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() => _busy = true);
    // Building the fake response is heavy too, so it also runs off the main
    // isolate. Strings are immutable, so sending it back costs nothing.
    final body = await buildFakeFeedJsonInBackground(_postCount);
    if (!mounted) return;
    setState(() {
      _body = body;
      _busy = false;
      _status =
          'Response ready: ${formatBytes(body.length)}. '
          'Now parse it both ways and watch the spinner.';
    });
  }

  Future<void> _parse({required bool inIsolate}) async {
    final body = _body!;
    setState(() {
      _busy = true;
      _status = 'Parsing...';
    });
    // Give the button a frame to show that it is pressed.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final (posts, took) = await timed(() async {
      if (inIsolate) {
        // The String goes in by reference (immutable, so shared). The parsed
        // list comes back without a copy: compute returns with Isolate.exit.
        return compute(parseFeed, body);
      }
      return parseFeed(body); // Blocks the main isolate. The spinner stops.
    });

    if (!mounted) return;
    setState(() {
      _posts = posts;
      _busy = false;
      _status =
          '${inIsolate ? 'compute' : 'Main isolate'}: '
          '${posts.length} posts in ${took.inMilliseconds} ms.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = _body != null;
    return ScenarioPage(
      title: 'Large API response',
      api: 'compute()',
      description:
          'A feed API returns ${_postCount ~/ 1000}k posts as JSON. Decoding, '
          'creating objects and sorting is all Dart work, so on the main '
          'isolate it freezes the screen. compute() moves it to a new isolate '
          'that exits when the result is ready.',
      busy: _busy || !ready,
      status: _status,
      onRunOnMain: () => _parse(inIsolate: false),
      onRunInIsolate: () => _parse(inIsolate: true),
      result: _posts.isEmpty
          ? null
          : Column(
              children: [
                for (final post in _posts.take(5))
                  ListTile(
                    dense: true,
                    title: Text(post.author),
                    subtitle: Text(post.text, maxLines: 1),
                    trailing: Text('${post.likes} likes'),
                  ),
              ],
            ),
    );
  }
}
