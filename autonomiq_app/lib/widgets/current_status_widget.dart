import 'package:flutter/material.dart';
import '../widgets/summary_status_box.dart';
import '../widgets/code_card.dart';

class CurrentStatusWidget extends StatelessWidget {
  final List<Map<String, String>> dtcs;

  const CurrentStatusWidget({super.key, required this.dtcs});

  @override
  Widget build(BuildContext context) {
    final hasIssues = dtcs.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SummaryStatusBox(hasIssues: hasIssues),
        const SizedBox(height: 12),
        ...dtcs.map((code) => CodeCard(
              code: code['code'] ?? 'Unknown',
              description: code['description'] ?? 'No description',
            )),
      ],
    );
  }
}
