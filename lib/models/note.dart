import 'package:cloud_firestore/cloud_firestore.dart';

/// Estado de sincronização de uma nota entre o SQLite e o Firestore.
enum SyncStatus {
  /// A versão local é igual à versão da nuvem.
  synced,

  /// A nota foi criada/alterada localmente e ainda precisa ser enviada.
  pending,

  /// A nota foi excluída definitivamente no aparelho e a exclusão
  /// ainda precisa ser enviada para o Firestore.
  pendingPurge,
}

class Note {
  /// Chave primária do SQLite (existe apenas no aparelho).
  final int? id;

  /// Identificador global (UUID). É o ID do documento no Firestore e
  /// liga a linha do SQLite ao documento da nuvem.
  final String remoteId;

  /// UID do usuário autenticado (Firebase Auth) dono da nota.
  final String uid;

  final String title;
  final String content;
  final String category;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Indica se a nota está na lixeira.
  final bool isDeleted;
  final DateTime? deletedAt;

  final SyncStatus syncStatus;

  const Note({
    this.id,
    required this.remoteId,
    required this.uid,
    required this.title,
    required this.content,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.syncStatus = SyncStatus.pending,
  });

  /// Data formatada da última atualização (dd/MM/aaaa HH:mm).
  String get date => formatDate(updatedAt);

  static String formatDate(DateTime value) {
    final d = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Note copyWith({
    int? id,
    String? title,
    String? content,
    String? category,
    DateTime? updatedAt,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    SyncStatus? syncStatus,
  }) {
    return Note(
      id: id ?? this.id,
      remoteId: remoteId,
      uid: uid,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  /// Converte para uma linha da tabela `notes` do SQLite.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'remote_id': remoteId,
      'uid': uid,
      'title': title,
      'content': content,
      'category': category,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
      'sync_status': syncStatus.name,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as int?,
      remoteId: map['remote_id'] as String,
      uid: map['uid'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      category: map['category'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.parse(map['deleted_at'] as String),
      syncStatus: SyncStatus.values.byName(
        map['sync_status'] as String? ?? SyncStatus.pending.name,
      ),
    );
  }

  /// Converte para o documento salvo em `users/{uid}/notes/{remoteId}`.
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'title': title,
      'content': content,
      'category': category,
      'createdAt': Timestamp.fromDate(createdAt.toUtc()),
      'updatedAt': Timestamp.fromDate(updatedAt.toUtc()),
      'isDeleted': isDeleted,
      'deletedAt': deletedAt == null
          ? null
          : Timestamp.fromDate(deletedAt!.toUtc()),
    };
  }

  factory Note.fromFirestore(String docId, Map<String, dynamic> data) {
    return Note(
      remoteId: docId,
      uid: data['uid'] as String,
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      category: data['category'] as String? ?? 'Geral',
      createdAt: _readDate(data['createdAt']) ?? DateTime.now().toUtc(),
      updatedAt: _readDate(data['updatedAt']) ?? DateTime.now().toUtc(),
      isDeleted: data['isDeleted'] as bool? ?? false,
      deletedAt: _readDate(data['deletedAt']),
      syncStatus: SyncStatus.synced,
    );
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }
}
