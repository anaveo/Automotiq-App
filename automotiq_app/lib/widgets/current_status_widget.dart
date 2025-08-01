import 'package:automotiq_app/screens/dtc_detail_screen.dart';
import 'package:automotiq_app/widgets/summary_status_box.dart';
import 'package:flutter/material.dart';
import '../services/dtc_database_service.dart';

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
    _dtcFuture = _loadDtcDetails();
  }

  @override
  void didUpdateWidget(covariant CurrentStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dtcs != widget.dtcs) {
      _dtcFuture = _loadDtcDetails();
    }
  }

  Future<Map<String, Map<String, String>>> _loadDtcDetails() async {
    final Map<String, Map<String, String>> result = {};
    for (final code in widget.dtcs) {
      final info = await DtcDatabaseService().getDtc(code);
      result[code] = info;
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
          return Text('Error loading DTCs: ${snapshot.error}');
        }

        final dtcDetails = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SummaryStatusBox(hasIssues: widget.dtcs.isNotEmpty),
            SizedBox(height: 16),
            Column(
              children: widget.dtcs.map((code) {
                final description =
                    dtcDetails[code]?['description'] ??
                    'No description available';
                final cause =
                    dtcDetails[code]?['cause'] ?? 'No cause available';

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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DtcDetailScreen(
                            code: code,
                            description: description,
                            cause: cause,
                          ),
                        ),
                      );
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
