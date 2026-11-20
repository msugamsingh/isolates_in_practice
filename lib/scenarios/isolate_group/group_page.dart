import 'package:flutter/material.dart';

import '../../common/scenario_page.dart';
import 'group_logic.dart';

/// Scenario: not an app feature, a lab. It shows what being in one isolate
/// group means, with numbers measured on your device.
class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  bool _busy = false;
  String _status =
      'Run the experiments. They allocate a few hundred MB '
      'for a moment, and some of them block the main isolate on purpose.';
  String? _statics;
  List<Measurement> _into = const [];
  List<Measurement> _back = const [];

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _status = 'Running...';
    });
    final (mainValue, workerValue) = await GroupLab.separateStatics();
    final into = await GroupLab.sendInto();
    final back = await GroupLab.resultBack();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status =
          'Done. Times are from this device; run it twice, the first '
          'run includes warm-up.';
      _statics =
          'Main set launchCount = $mainValue. The worker, running the '
          'same code in the same group, saw ${workerValue - 1} and made it '
          '$workerValue. Main still has $mainValue.';
      _into = into;
      _back = back;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ScenarioPage(
      title: 'Isolate group lab',
      api: 'Isolate groups',
      description:
          'Your main isolate and every isolate it starts with Isolate.spawn '
          '(and so Isolate.run and compute) form one isolate group. The VM '
          'shares their code and stores their objects in one heap, but no '
          'isolate can reach another\'s objects. You only see the group '
          'through what it makes cheap.',
      busy: _busy,
      status: _status,
      extraActions: [
        FilledButton.icon(
          onPressed: _busy ? null : _run,
          icon: const Icon(Icons.science_outlined),
          label: const Text('Run experiments'),
        ),
      ],
      result: _statics == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1. Same code, separate memory', style: text.titleSmall),
                Text(_statics!),
                const SizedBox(height: 16),
                Text(
                  '2. Main isolate blocked by send()',
                  style: text.titleSmall,
                ),
                _Table(_into),
                const SizedBox(height: 16),
                Text(
                  '3. Result back to main, end to end',
                  style: text.titleSmall,
                ),
                _Table(_back),
                const SizedBox(height: 8),
                Text(
                  'Isolate.exit hands results over only inside one group. An '
                  'isolate started with Isolate.spawnUri is in a new group, so '
                  'Isolate.exit to it throws.',
                  style: text.bodySmall,
                ),
              ],
            ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table(this.rows);
  final List<Measurement> rows;

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2)},
      children: [
        for (final m in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(m.label),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('${m.millis.toStringAsFixed(2)} ms, ${m.what}'),
              ),
            ],
          ),
      ],
    );
  }
}
