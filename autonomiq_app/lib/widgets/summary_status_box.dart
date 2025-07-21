import 'package:flutter/material.dart';

class SummaryStatusBox extends StatelessWidget {
  final bool hasIssues;

  const SummaryStatusBox({super.key, required this.hasIssues});

  @override
  Widget build(BuildContext context) {
    final borderColor = hasIssues ? Colors.amber : Colors.green;
    final message = hasIssues
        ? "Issues detected, please see the codes below"
        : "No problems detected";

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: borderColor),
      ),
    );
  }
}
