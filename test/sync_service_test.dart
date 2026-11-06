import 'package:bloco_de_nota_turma_a/models/note.dart';
import 'package:bloco_de_nota_turma_a/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

Note note(
  String id, {
  required DateTime updatedAt,
  SyncStatus status = SyncStatus.synced,
  String content = 'texto',
}) {
  return Note(
    remoteId: id,
    uid: 'user-1',
    title: id,
    content: content,
    category: 'Geral',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: updatedAt,
    syncStatus: status,
  );
}

void main() {
  final t1 = DateTime.utc(2026, 1, 1, 10);
  final t2 = DateTime.utc(2026, 1, 1, 11);

  test('nota que só existe na nuvem é inserida no aparelho', () {
    final plan = SyncService.merge([], [note('a', updatedAt: t1)]);

    expect(plan.toInsertLocally.map((n) => n.remoteId), ['a']);
    expect(plan.toUpdateLocally, isEmpty);
    expect(plan.toDeleteLocally, isEmpty);
  });

  test('versão mais nova da nuvem substitui a local sincronizada', () {
    final plan = SyncService.merge(
      [note('a', updatedAt: t1)],
      [note('a', updatedAt: t2, content: 'novo')],
    );

    expect(plan.toUpdateLocally.single.content, 'novo');
  });

  test('alteração local pendente mais nova é mantida (last-write-wins)', () {
    final plan = SyncService.merge(
      [note('a', updatedAt: t2, status: SyncStatus.pending)],
      [note('a', updatedAt: t1)],
    );

    expect(plan.isEmpty, isTrue);
  });

  test('alteração remota mais nova vence a pendente local', () {
    final plan = SyncService.merge(
      [note('a', updatedAt: t1, status: SyncStatus.pending)],
      [note('a', updatedAt: t2, content: 'remoto')],
    );

    expect(plan.toUpdateLocally.single.content, 'remoto');
  });

  test('nota sincronizada que sumiu da nuvem é removida do aparelho', () {
    final plan = SyncService.merge([note('a', updatedAt: t1)], []);

    expect(plan.toDeleteLocally.single.remoteId, 'a');
  });

  test('nota pendente que ainda não existe na nuvem não é removida', () {
    final plan = SyncService.merge([
      note('a', updatedAt: t1, status: SyncStatus.pending),
    ], []);

    expect(plan.isEmpty, isTrue);
  });

  test('resolveConflict mantém a versão local em caso de empate', () {
    final local = note('a', updatedAt: t1, status: SyncStatus.pending);
    final remote = note('a', updatedAt: t1);

    expect(
      identical(SyncService.resolveConflict(local, remote), local),
      isTrue,
    );
  });
}
