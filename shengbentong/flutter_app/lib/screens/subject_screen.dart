/// 科目列表：本地数据展示 + 手动刷新(重同步) + 题库更新提示
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import 'chapter_screen.dart';
import 'favorites_screen.dart';
import 'stats_screen.dart';
import 'wrong_book_screen.dart';

class SubjectScreen extends StatefulWidget {
  const SubjectScreen({super.key});

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  DbService? _db;
  List<SubjectStat> _stats = [];
  Map<String, Object?> _summary = const {};
  bool _loading = true;
  bool _syncing = false;
  String? _offlineHint;
  bool _updateAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
    _checkUpdate();
  }

  Future<void> _load() async {
    final db = await DbService.open();
    final stats = await db.subjectsWithStats();
    final summary = await db.statsSummary();
    if (!mounted) return;
    setState(() {
      _db = db;
      _stats = stats;
      _summary = summary;
      _loading = false;
    });
  }

  Future<void> _checkUpdate() async {
    try {
      final api = await createApiFromPrefs();
      final update = await SyncService(api: api, db: _db ?? (await DbService.open()))
          .hasUpdate();
      if (mounted) setState(() => _updateAvailable = update);
    } catch (_) {/* 离线静默 */}
  }

  Future<void> _resync() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _syncing = true;
      _offlineHint = null;
    });
    try {
      final api = await createApiFromPrefs();
      final db = _db ?? await DbService.open();
      final r = await SyncService(api: api, db: db).run((s) {
        if (mounted) setState(() => _offlineHint = s);
      });
      await _load();
      await _checkUpdate();
      messenger.showSnackBar(SnackBar(
          content: Text('更新完成：${r.questions}题'),
          backgroundColor: okGreen));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _offlineHint = '${e.message} —— 请检查PC是否启动');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _confirmLogout() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('重新绑定？'),
        content: const Text('将清除服务器地址并重新全量同步（本地答题进度保留）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定')),
        ],
      ),
    );
    if (ok == true) {
      await sp.remove(ApiConfig.ipKey);
      if (mounted) Navigator.pushReplacementNamed(context, '/bind');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的科目',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              tooltip: '重新绑定',
              onPressed: _confirmLogout,
              icon: const Icon(Icons.settings_input_component)),
        ],
      ),
      body: Column(children: [
        if (_updateAvailable)
          MaterialBanner(
            content: const Text('题库有更新，是否刷新？'),
            leading: const Icon(Icons.update, color: brandBlue),
            actions: [
              TextButton(onPressed: _resync, child: const Text('立即刷新')),
              TextButton(onPressed: () => setState(() => _updateAvailable = false), child: const Text('稍后')),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Text(_syncing ? (_offlineHint ?? '正在同步…') : '共 ${_stats.length} 个科目',
                style: TextStyle(color: Colors.grey.shade600)),
            const Spacer(),
            IconButton(
                tooltip: '重新同步',
                onPressed: _syncing ? null : _resync,
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync)),
          ]),
        ),
        _entryCards(),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _entryCards() {
    final pending = (_summary['pending_upload'] as int?) ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(children: [
        _entryCard(Icons.error_outline, '错题本', '${_summary['wrong_book'] ?? 0}',
            badRed, () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const WrongBookScreen()));
          _load();
        }),
        const SizedBox(width: 10),
        _entryCard(Icons.bookmark_border, '收藏夹', '${_summary['favorites'] ?? 0}',
            brandBlue, () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const FavoritesScreen()));
          _load();
        }),
        const SizedBox(width: 10),
        _entryCard(Icons.insights, '我的统计', '$pending', Colors.orange, () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const StatsScreen()));
          _load();
        }),
      ]),
    );
  }

  Widget _entryCard(IconData icon, String label, String badge, Color color,
      VoidCallback onTap) {
    return Expanded(
        child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: color.withValues(alpha: .18))),
                child: Column(children: [
                  Stack(clipBehavior: Clip.none, children: [
                    Icon(icon, size: 26, color: color),
                    if (badge != '0')
                      Positioned(top: -5, right: -9, child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(9)),
                          constraints:
                              const BoxConstraints(minWidth: 17),
                          child: Text(badge,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)))),
                  ]),
                  const SizedBox(height: 6),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w500)),
                ]))));
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_stats.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
        const SizedBox(height: 8),
        const Text('暂无内容，请先在PC端导入题库后点击右上角同步'),
        const SizedBox(height: 14),
        FilledButton(onPressed: _resync, child: const Text('重新同步')),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _resync,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _stats.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final st = _stats[i];
          return Card(
            elevation: 1.5,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ChapterScreen(subject: st.subject))),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Stack(alignment: Alignment.center, children: [
                    SizedBox(
                        width: 52,
                        height: 52,
                        child: CircularProgressIndicator(
                            value: 0,
                            strokeWidth: 5,
                            backgroundColor: Colors.grey.shade200,
                            color: brandBlue)),
                    Text('${st.questions}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                      Text(st.subject.name,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${st.chapters} 章 · ${st.questions} 题',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade600)),
                    ])),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
