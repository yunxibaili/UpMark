/// 我的统计 —— 数字卡片版（T-105：fl_chart 待后续审批再上图表）。
/// 含分科目正确率表与"上传答题记录到PC"（sync_queue 批量上报）。
library;

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, Object?> _summary = {};
  List<Map<String, Object?>> _bySubject = [];
  String? _lastSync;
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// 先加载summary再尝试自动上传——否则pending读到0会错误跳过（T-105联调发现的竞态）
  Future<void> _init() async {
    await _reload();
    _tryUpload(silent: true);
  }

  Future<void> _reload() async {
    final db = await DbService.open();
    final summary = await db.statsSummary();
    final bySubject = await db.accuracyBySubject();
    final last = await SyncService.lastSyncTime();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _bySubject = bySubject;
      _lastSync = last;
      _loading = false;
    });
  }

  /// 静默尝试上传（进入页面时自动）；失败不打扰用户
  Future<void> _tryUpload({bool silent = false}) async {
    if (_uploading) return;
    final pending = (_summary['pending_upload'] as int?) ?? 0;
    if (!silent && pending == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('暂无待上传记录'),
          backgroundColor: okGreen,
          duration: Duration(seconds: 1)));
      return;
    }
    setState(() => _uploading = true);
    try {
      final api = await createApiFromPrefs();
      final db = await DbService.open();
      final r = await SyncService(api: api, db: db).uploadPending();
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(r.pushed == 0 && r.duplicates == 0
                ? '没有需要上传的记录'
                : '已上传 ${r.pushed} 条${r.duplicates > 0 ? "（去重${r.duplicates}条）" : ""}'),
            backgroundColor: okGreen));
      }
    } on ApiException catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('上传失败：${e.message}\n进度已存本地，联网后再试',
                    style: const TextStyle(height: 1.4)),
            backgroundColor: badRed));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('我的统计',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: brandBlue, foregroundColor: Colors.white),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(padding: const EdgeInsets.all(14), children: [
                _cardGrid(),
                _uploadCard(),
                const SizedBox(height: 6),
                _subjectTable(),
              ]),
            ),
    );
  }

  Widget _cardGrid() {
    final acc = _summary['accuracy'] as double?;
    return GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.15,
        children: [
          _statCard('${_summary['answered'] ?? 0}', '累计作答(次)', brandBlue),
          _statCard(acc == null ? '—' : '${(acc * 100).toStringAsFixed(1)}%',
              '总正确率', okGreen),
          _statCard('${_summary['wrong_book'] ?? 0}', '错题本', badRed),
          _statCard('${_summary['favorites'] ?? 0}', '收藏', brandBlue),
          _statCard('${_summary['pending_upload'] ?? 0}', '待上传', Colors.orange),
          _statCard(_lastSync == null ? '从未' : _lastSync!.substring(5, 16),
              '上次同步', Colors.grey.shade600),
        ]);
  }

  Widget _statCard(String value, String label, Color color) {
    return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: color))),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              textAlign: TextAlign.center),
        ]));
  }

  Widget _uploadCard() {
    final pending = (_summary['pending_upload'] as int?) ?? 0;
    return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor:
                    pending == 0 ? Colors.grey.shade400 : brandBlue,
                minimumSize: const Size.fromHeight(48)),
            icon: _uploading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cloud_upload),
            label: Text(pending == 0
                ? '答题记录已全部同步'
                : '上传答题记录到PC（$pending 条待传）'),
            onPressed: _uploading ? null : () => _tryUpload()));
  }

  Widget _subjectTable() {
    if (_bySubject.isEmpty) {
      return Padding(padding: const EdgeInsets.only(top: 20),
          child: Center(child: Text('还没有作答记录，先去刷几题吧',
              style: TextStyle(color: Colors.grey.shade600))));
    }
    return Card(elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(padding: const EdgeInsets.all(6),
          child: Table(
            columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
            border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade200)),
            children: [
              TableRow(decoration: BoxDecoration(color: Colors.grey.shade50),
                  children: [_cell('科目', bold: true), _cell('已答', bold: true), _cell('正确率', bold: true)]),
              for (final r in _bySubject)
                TableRow(children: [
                  _cell('${r['subject']}'),
                  _cell('${r['answered']}'),
                  _cell(_pct(r), color: ((r['correct'] as int? ?? 0)) / ((r['answered'] as int? ?? 1)) >= 0.8 ? okGreen : badRed),
                ]),
            ])));
  }

  String _pct(Map<String, Object?> r) {
    final a = r['answered'] as int? ?? 0;
    final c = r['correct'] as int? ?? 0;
    if (a == 0) return '—';
    return '${(c / a * 100).toStringAsFixed(0)}%';
  }

  Widget _cell(String t, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
      child: Text(t,
          style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              color: color ?? Colors.black87)));
}
