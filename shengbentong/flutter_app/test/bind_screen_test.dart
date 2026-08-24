/// 绑定页校验逻辑测试（不触网）
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shengbentong/screens/bind_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpIt(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: BindScreen()));
    await tester.pump();
  }

  testWidgets('空输入 → 提示输入IP，不发请求', (tester) async {
    await pumpIt(tester);
    await tester.tap(find.text('连接并全量同步'));
    await tester.pump();
    expect(find.text('请输入PC的IP地址'), findsOneWidget);
  });

  testWidgets('非法IP → 前端拦截提示格式错误', (tester) async {
    await pumpIt(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'PC IP 地址'), 'abc');
    await tester.tap(find.text('连接并全量同步'));
    await tester.pump();
    expect(find.textContaining('IP格式不正确'), findsOneWidget);
  });

  testWidgets('非法端口 → 拦截提示范围', (tester) async {
    await pumpIt(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'PC IP 地址'), '192.168.1.5');
    await tester.enterText(
        find.widgetWithText(TextField, '端口'), '99999');
    await tester.tap(find.text('连接并全量同步'));
    await tester.pump();
    expect(find.textContaining('端口须为'), findsOneWidget);
  });
}
