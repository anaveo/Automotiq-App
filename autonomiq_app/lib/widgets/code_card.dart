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
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        title: Text(description),
        onTap: () {
          // no action yet
        },
      ),
    );
  }
}
