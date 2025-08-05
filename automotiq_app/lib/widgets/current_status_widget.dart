import 'package:automotiq_app/widgets/summary_status_box.dart';
import 'package:flutter/material.dart';
import '../services/dtc_database_service.dart';
import 'package:automotiq_app/utils/logger.dart';

class CurrentStatusWidget extends StatefulWidget {
  final List<String> dtcs;

  const CurrentStatusWidget({super.key, required this.dtcs});

  @override
  State<CurrentStatusWidget> createState() => _CurrentStatusWidgetState();
}

class _CurrentStatusWidgetState extends State<CurrentStatusWidget> {
  Map<String, Map<String, String>> dtcDetails = {};

  late Future<Map<String, Map<String, String>>> _dtcFuture;

  @override
  void initState() {
    super.initState();
    AppLogger.logInfo(
      'Initializing CurrentStatusWidget with DTCs: ${widget.dtcs}',
    );
    _dtcFuture = _loadDtcDetails();
  }

  @override
  void didUpdateWidget(covariant CurrentStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dtcs != widget.dtcs) {
      AppLogger.logInfo('DTCs updated, reloading details: ${widget.dtcs}');
      _dtcFuture = _loadDtcDetails();
    }
  }

  Future<Map<String, Map<String, String>>> _loadDtcDetails() async {
    final Map<String, Map<String, String>> result = {};
    for (final code in widget.dtcs) {
      final info = await DtcDatabaseService().getDtc(code);
      result[code] = info;
      if (info['description']?.isEmpty ?? true) {
        AppLogger.logWarning('No description found for DTC: $code');
      } else {
        AppLogger.logInfo(
          'Loaded description for DTC $code: ${info['description']}',
        );
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Map<String, String>>>(
      future: _dtcFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          AppLogger.logError('Error loading DTCs: ${snapshot.error}');
          return const Text('Error loading DTC details');
        }

        final dtcDetails = snapshot.data ?? {};

        if (widget.dtcs.isEmpty) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SummaryStatusBox(hasIssues: false),
              SizedBox(height: 16),
              Text(
                'No DTCs detected',
                style: TextStyle(color: Colors.greenAccent),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SummaryStatusBox(hasIssues: widget.dtcs.isNotEmpty),
            const SizedBox(height: 16),
            Column(
              children: widget.dtcs.map((code) {
                final description =
                    dtcDetails[code]?['description']?.isNotEmpty ?? false
                    ? dtcDetails[code]!['description']!
                    : 'Description not available';
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: Text(
                      code,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    title: Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    onTap: () {
                      // TODO: To be added in a future release
                    },
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}
