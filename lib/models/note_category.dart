import 'package:cloud_firestore/cloud_firestore.dart';

import 'note.dart';

/// Categoria usada para organizar as notas (ex.: Estudos, Trabalho).
class NoteCategory {
  static const String defaultName = 'Geral';
  static const List<String> defaults = [
    'Geral',
    'Estudos',
    'Trabalho',
    'Pessoal',
  ];

  final int? id;
  final String remoteId;
  final String uid;
  final String name;
  final DateTime createdAt;
  final SyncStatus syncStatus;

  const NoteCategory({
    this.id,
    required this.remoteId,
    required this.uid,
    required this.name,
    required this.createdAt,
    this.syncStatus = SyncStatus.pending,
  });

  NoteCategory copyWith({SyncStatus? syncStatus}) {
    return NoteCategory(
      id: id,
      remoteId: remoteId,
      uid: uid,
      name: name,
      createdAt: createdAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'remote_id': remoteId,
      'uid': uid,
      'name': name,
      'created_at': createdAt.toUtc().toIso8601String(),
      'sync_status': syncStatus.name,
    };
  }

  factory NoteCategory.fromMap(Map<String, dynamic> map) {
    return NoteCategory(
      id: map['id'] as int?,
      remoteId: map['remote_id'] as String,
      uid: map['uid'] as String,
      name: map['name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      syncStatus: SyncStatus.values.byName(
        map['sync_status'] as String? ?? SyncStatus.pending.name,
      ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'name': name,
      'createdAt': Timestamp.fromDate(createdAt.toUtc()),
    };
  }

  factory NoteCategory.fromFirestore(String docId, Map<String, dynamic> data) {
    final created = data['createdAt'];
    return NoteCategory(
      remoteId: docId,
      uid: data['uid'] as String,
      name: data['name'] as String,
      createdAt: created is Timestamp
          ? created.toDate().toUtc()
          : DateTime.now().toUtc(),
      syncStatus: SyncStatus.synced,
    );
  }
}
