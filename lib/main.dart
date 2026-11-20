import 'package:flutter/material.dart';

import 'scenarios/audio_merge/audio_page.dart';
import 'scenarios/file_hash/file_hash_page.dart';
import 'scenarios/isolate_group/group_page.dart';
import 'scenarios/json_feed/feed_page.dart';
import 'scenarios/lottie_bundle/lottie_page.dart';
import 'scenarios/photo_filter/photo_page.dart';
import 'scenarios/thumbnail_worker/thumbnail_page.dart';

void main() => runApp(const IsolatesApp());

class IsolatesApp extends StatelessWidget {
  const IsolatesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Isolates in practice',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

class _Scenario {
  const _Scenario(this.title, this.api, this.icon, this.page);
  final String title;
  final String api;
  final IconData icon;
  final Widget Function() page;
}

final _scenarios = [
  _Scenario('Large API response', 'compute()', Icons.data_object, FeedPage.new),
  _Scenario('Photo filter', 'Isolate.run()', Icons.photo_filter, PhotoPage.new),
  _Scenario('Lottie bundle', 'Isolate.run()', Icons.animation, LottiePage.new),
  _Scenario(
    'Merge audio clips',
    'Isolate.run()',
    Icons.graphic_eq,
    AudioPage.new,
  ),
  _Scenario(
    'Large file checksum',
    'Isolate.spawn() + progress + cancel',
    Icons.fingerprint,
    FileHashPage.new,
  ),
  _Scenario(
    'Gallery thumbnails',
    'Long-lived isolate',
    Icons.grid_view,
    ThumbnailPage.new,
  ),
  _Scenario(
    'Isolate group lab',
    'Isolate groups',
    Icons.science_outlined,
    GroupPage.new,
  ),
];

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Isolates in practice')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Real tasks that are too heavy for the main isolate. Most '
              'screens can run the same work on the main isolate (watch the '
              'spinner freeze) or in a background isolate. Run in profile '
              'mode on a real phone for honest timings.',
            ),
          ),
          for (final s in _scenarios)
            ListTile(
              leading: Icon(s.icon),
              title: Text(s.title),
              subtitle: Text(s.api),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => s.page())),
            ),
        ],
      ),
    );
  }
}
