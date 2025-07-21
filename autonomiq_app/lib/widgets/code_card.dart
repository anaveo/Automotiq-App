import 'package:flutter/material.dart';

class CodeCard extends StatelessWidget {
  final String code;
  final String description;

  const CodeCard({super.key, required this.code, required this.description});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Text(code,
            style: Theme.of(context).textTheme.titleMedium),
        title: Text(description,
          style: Theme.of(context).textTheme.bodyMedium),
        onTap: () {
          // no action yet
        },
      ),
    );
  }
}
