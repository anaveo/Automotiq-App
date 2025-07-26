import 'package:flutter/material.dart';

class DtcDetailScreen extends StatelessWidget {
  final String code;
  final String description;
  final String cause;

  const DtcDetailScreen({
    super.key,
    required this.code,
    required this.description,
    required this.cause,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('About This Code: $code')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Description:",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(description),
            const SizedBox(height: 12),
            Text(
              "Possible Cause:",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(cause),
          ],
        ),
      ),
    );
  }
}
