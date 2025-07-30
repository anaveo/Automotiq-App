import 'package:flutter/material.dart';
import 'ble_scan_screen.dart';

class ObdSetupScreen extends StatelessWidget {
  const ObdSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Vehicle')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.car_repair,
              color: Colors.deepPurpleAccent,
              size: 80,
            ),
            const SizedBox(height: 24),
            Text(
              'Plug in your new OBD2 device\nand turn on your car.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BleScanScreen()),
                  );
                },
                style: Theme.of(context).elevatedButtonTheme.style,
                child: const Text('Proceed'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
