/// 升本通 App 入口：路由决策（已绑定→科目列表 / 未绑定→绑定页）
library;

import 'package:flutter/material.dart';

import 'services/api_service.dart';
import 'screens/bind_screen.dart';
import 'screens/subject_screen.dart';

const brandBlue = Color(0xFF4A90D9);
const okGreen = Color(0xFF52C41A);
const badRed = Color(0xFFFF4D4F);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bound = await hasBindingSaved();
  runApp(ShengBenTongApp(initialRoute: bound ? '/subjects' : '/bind'));
}

class ShengBenTongApp extends StatelessWidget {
  final String initialRoute;
  const ShengBenTongApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '升本通',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brandBlue),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      initialRoute: initialRoute,
      routes: {
        '/bind': (_) => const BindScreen(),
        '/subjects': (_) => const SubjectScreen(),
      },
    );
  }
}
