/// 绑定PC：输入IP+端口 → 前端校验 → bind探测 → 全量同步 → 进科目列表
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';

class BindScreen extends StatefulWidget {
  const BindScreen({super.key});

  @override
  State<BindScreen> createState() => _BindScreenState();
}

class _BindScreenState extends State<BindScreen> {
  final _ip = TextEditingController();
  final _port = TextEditingController(text: '8000');
  String? _error;
  bool _busy = false;
  String _stage = '';

  static final _ipRegex =
      RegExp(r'^(\d{1,3}\.){3}\d{1,3}$|^([a-fA-F0-9:]+:+[a-fA-F0-9]+)$');

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      final saved = sp.getString(ApiConfig.ipKey);
      if (saved != null && mounted) _ip.text = saved;
    });
  }

  String? _validateLocal() {
    final ip = _ip.text.trim();
    final portText = _port.text.trim();
    if (ip.isEmpty) return '请输入PC的IP地址';
    if (!_ipRegex.hasMatch(ip)) return 'IP格式不正确（示例 192.168.1.100）';
    final port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) return '端口须为1~65535的数字';
    return null;
  }

  Future<void> _connectAndSync() async {
    final localErr = _validateLocal();
    setState(() => _error = localErr);
    if (localErr != null) return; // 前端校验拦截，不发送请求

    setState(() {
      _busy = true;
      _stage = '正在连接PC…';
    });

    final ip = _ip.text.trim();
    final port = int.parse(_port.text.trim());

    try {
      final api = ApiService(baseUrl: 'http://$ip:$port');
      await api.bind(); // 探测
      await ApiConfig.save(ip, port);

      setState(() => _stage = '连接成功，开始全量同步…');
      final db = await DbService.open();
      final result = await SyncService(api: api, db: db).run((stage) {
        if (mounted) setState(() => _stage = stage);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '同步完成：${result.subjects}科目 / ${result.questions}题 / '
              '${result.elapsed.inMilliseconds}ms'),
          backgroundColor: okGreen));
      Navigator.pushReplacementNamed(context, '/subjects');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '同步失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.school, size: 72, color: brandBlue),
                const SizedBox(height: 12),
                const Text('升本通',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('绑定局域网内的PC服务端后开始学习',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 28),
                TextField(
                  controller: _ip,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                      labelText: 'PC IP 地址',
                      hintText: '192.168.1.100',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.computer)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '端口', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                if (_busy)
                  Column(children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 10),
                    Text(_stage, style: const TextStyle(color: Colors.black54)),
                  ])
                else
                  FilledButton.icon(
                    onPressed: _connectAndSync,
                    icon: const Icon(Icons.link),
                    label: const Text('连接并全量同步',
                        style: TextStyle(fontSize: 16)),
                    style: FilledButton.styleFrom(
                        backgroundColor: brandBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: badRed.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: badRed),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(color: badRed))),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                      onPressed: _busy ? null : _connectAndSync,
                      child: const Text('重试')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
