import 'package:bloco_de_nota_turma_a/models/note.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime.utc(2026, 1, 10, 8, 30);
  final updated = DateTime.utc(2026, 1, 11, 9, 45);

  Note sample() => Note(
    id: 7,
    remoteId: 'abc-123',
    uid: 'user-1',
    title: 'Prova',
    content: 'Estudar Flutter',
    category: 'Estudos',
    createdAt: created,
    updatedAt: updated,
  );

  test('toMap/fromMap preserva os dados do SQLite', () {
    final note = Note.fromMap(sample().toMap());

    expect(note.id, 7);
    expect(note.remoteId, 'abc-123');
    expect(note.category, 'Estudos');
    expect(note.createdAt, created);
    expect(note.updatedAt, updated);
    expect(note.isDeleted, isFalse);
    expect(note.syncStatus, SyncStatus.pending);
  });

  test('toFirestore/fromFirestore usa Timestamp e marca como sincronizada', () {
    final data = sample()
        .copyWith(isDeleted: true, deletedAt: updated)
        .toFirestore();

    expect(data['uid'], 'user-1');
    expect(data['updatedAt'], isA<Timestamp>());
    expect(data.containsKey('id'), isFalse);

    final note = Note.fromFirestore('abc-123', data);
    expect(note.remoteId, 'abc-123');
    expect(note.updatedAt, updated);
    expect(note.isDeleted, isTrue);
    expect(note.deletedAt, updated);
    expect(note.syncStatus, SyncStatus.synced);
  });

  test('copyWith pode limpar deletedAt ao restaurar da lixeira', () {
    final trashed = sample().copyWith(isDeleted: true, deletedAt: updated);
    final restored = trashed.copyWith(isDeleted: false, clearDeletedAt: true);

    expect(restored.isDeleted, isFalse);
    expect(restored.deletedAt, isNull);
  });
}
