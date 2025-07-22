import 'package:autonomiq_app/widgets/summary_status_box.dart';
import 'package:flutter/material.dart';
import '../services/dtc_database_service.dart';
import 'code_card.dart';

class CurrentStatusWidget extends StatefulWidget {
  final List<String> dtcs;

  const CurrentStatusWidget({
    super.key,
    required this.dtcs,
  });

  @override
  State<CurrentStatusWidget> createState() => _CurrentStatusWidgetState();
}

class _CurrentStatusWidgetState extends State<CurrentStatusWidget> {
  Map<String, Map<String, String>> dtcDetails = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadDtcDetails();
  }

  Future<void> _loadDtcDetails() async {
    final Map<String, Map<String, String>> result = {};
    for (final code in widget.dtcs) {
      final info = await DtcDatabaseService().getDtc(code);
      result[code] = info ??
          {
            'description': 'Unknown DTC',
            'cause': 'No data available.'
          };
    }

    setState(() {
      dtcDetails = result;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:[
        SummaryStatusBox(hasIssues: widget.dtcs.isNotEmpty),
        SizedBox(height: 16),
        Column(
          children: widget.dtcs.map((code) {
            final detail = dtcDetails[code];
            return CodeCard(
                code: code,
                description: detail?['description'] ?? '',
            );
          }).toList(),
          )
      ]
    );
  }
}
