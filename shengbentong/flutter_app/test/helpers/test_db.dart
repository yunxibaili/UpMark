/// 测试辅助：ffi初始化 + 每文件独立命名的临时库（避免并发锁与串扰）
library;

import 'package:path/path.dart' as pp;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shengbentong/services/db_service.dart';

void initFfi() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// 打开独立命名库；先清缓存再删旧文件，保证用例间完全隔离
Future<DbService> openTestDb(String fileName) async {
  initFfi();
  DbService.resetInstanceCache();
  final dir = await getDatabasesPath();
  final file = pp.join(dir, fileName);
  await databaseFactory.deleteDatabase(file);
  return DbService.open(file);
}
