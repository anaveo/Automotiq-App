import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:automotiq_app/providers/auth_provider.dart';
import 'package:automotiq_app/screens/login_screen.dart';
import '../mocks.mocks.dart';

void main() {
  late MockAppAuthProvider mockAuthProvider;

  setUp(() {
    mockAuthProvider = MockAppAuthProvider();
    when(mockAuthProvider.isLoading).thenReturn(false);
    when(mockAuthProvider.user).thenReturn(null);
  });

  testWidgets('triggers anonymous login on init', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppAuthProvider>.value(
        value: mockAuthProvider,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    verify(mockAuthProvider.signInAnonymously()).called(1);
  });

  testWidgets('shows email form on button tap', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppAuthProvider>.value(
        value: mockAuthProvider,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}