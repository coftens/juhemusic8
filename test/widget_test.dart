// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/app/app_shell.dart';
import 'package:flutter_app/api/api_config.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'php_api_base_url': 'http://example.com',
    });
    await ApiConfig.instance.load();

    // Avoid building Home tab in tests (it renders NetworkImage).
    await tester.pumpWidget(const MaterialApp(home: AppShell(initialTab: 1)));
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('搜索'), findsWidgets);
  });
}
