import 'package:flutter/material.dart';

void navigateToObdSetup(BuildContext context) {
  Navigator.pushNamed(context, '/obdSetup');
}

void navigateToHome(BuildContext context) {
  Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
}