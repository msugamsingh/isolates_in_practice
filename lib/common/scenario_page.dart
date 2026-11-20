import 'package:flutter/material.dart';

/// The frame every scenario uses.
///
/// - A spinner that never stops: if it freezes, the main isolate is busy.
/// - "Main isolate" and "Background isolate" buttons running the same work,
///   so you can compare them side by side.
/// - A status line and a result area.
class ScenarioPage extends StatelessWidget {
  const ScenarioPage({
    super.key,
    required this.title,
    required this.api,
    required this.description,
    required this.busy,
    required this.status,
    this.onRunOnMain,
    this.onRunInIsolate,
    this.extraActions = const [],
    this.result,
  });

  final String title;

  /// Which isolate API this scenario shows, e.g. "Isolate.run".
  final String api;
  final String description;
  final bool busy;
  final String status;

  /// The same work, done on the main isolate. Null hides the button.
  final VoidCallback? onRunOnMain;
  final VoidCallback? onRunInIsolate;
  final List<Widget> extraActions;
  final Widget? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Chip(label: Text(api)),
          const SizedBox(height: 8),
          Text(description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          const _Heartbeat(),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onRunOnMain != null)
                OutlinedButton.icon(
                  onPressed: busy ? null : onRunOnMain,
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Main isolate'),
                ),
              if (onRunInIsolate != null)
                FilledButton.icon(
                  onPressed: busy ? null : onRunInIsolate,
                  icon: const Icon(Icons.bolt),
                  label: const Text('Background isolate'),
                ),
              ...extraActions,
            ],
          ),
          const SizedBox(height: 12),
          Text(status, style: theme.textTheme.bodySmall),
          if (result != null) ...[const SizedBox(height: 16), result!],
        ],
      ),
    );
  }
}

/// Keeps animating while the main isolate is free. It stops when it is not.
class _Heartbeat extends StatelessWidget {
  const _Heartbeat();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox.square(dimension: 28, child: CircularProgressIndicator()),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'If this spinner stops, the main isolate is blocked and the UI is '
            'frozen.',
          ),
        ),
      ],
    );
  }
}

/// Runs [work] and returns its result together with how long it took.
Future<(T, Duration)> timed<T>(Future<T> Function() work) async {
  final watch = Stopwatch()..start();
  final result = await work();
  return (result, watch.elapsed);
}

String formatBytes(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(1)} KB';
  return '$bytes B';
}
