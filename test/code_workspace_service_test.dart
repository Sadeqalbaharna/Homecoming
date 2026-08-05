import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/code_workspace_service.dart';

void main() {
  test('active coding work automatically reacquires a known Homecoming repo', () async {
    final parent = await Directory.systemTemp.createTemp('kai_homecoming_ws_');
    final repo = Directory(
      '${parent.path}${Platform.pathSeparator}homecoming_app',
    );
    try {
      await repo.create();
      await Directory('${repo.path}${Platform.pathSeparator}lib').create();
      await File('${repo.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsString('name: homecoming_app');
      await CodeWorkspaceService.instance.addProject(repo.path);
      await CodeWorkspaceService.instance.setRoot(null);

      expect(
        await CodeWorkspaceService.instance.ensureHomecomingWorkspace(),
        isTrue,
      );
      expect(CodeWorkspaceService.instance.root, repo.path);
    } finally {
      await CodeWorkspaceService.instance.removeProject(repo.path);
      await CodeWorkspaceService.instance.setRoot(null);
      await parent.delete(recursive: true);
    }
  });

  test('listDir treats omitted-style root aliases as workspace root', () async {
    final temp = await Directory.systemTemp.createTemp('kai_ws_root_alias_');
    try {
      await File('${temp.path}${Platform.pathSeparator}sentinel.txt')
          .writeAsString('root marker');
      await CodeWorkspaceService.instance.setRoot(temp.path);

      final empty = await CodeWorkspaceService.instance.listDir('');
      final dot = await CodeWorkspaceService.instance.listDir('.');
      final slash = await CodeWorkspaceService.instance.listDir('/');

      expect(empty, contains('sentinel.txt'));
      expect(dot, empty);
      expect(slash, empty);
    } finally {
      await CodeWorkspaceService.instance.setRoot(null);
      await temp.delete(recursive: true);
    }
  });
}
