import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/note.dart';
import '../models/note_category.dart';
import '../services/firestore_service.dart';
import '../services/sync_service.dart';
import '../utils/sync_errors.dart';

/// Resultado de uma operação de escrita.
class SaveResult {
  final bool syncedToCloud;
  final String? error;

  const SaveResult.synced() : syncedToCloud = true, error = null;
  const SaveResult.pending(this.error) : syncedToCloud = false;

  String get message => syncedToCloud
      ? 'Salvo no aparelho e na nuvem.'
      : 'Salvo no aparelho. Será enviado à nuvem quando houver conexão.'
            '${error == null ? '' : '\n$error'}';
}

/// Resultado de uma sincronização completa.
class SyncReport {
  final int pushed;
  final int pulled;
  final String? error;

  const SyncReport({this.pushed = 0, this.pulled = 0, this.error});

  bool get success => error == null;
}

/// Ponto único de acesso aos dados das notas (padrão Repository).
///
/// A interface usa apenas esta classe. Ela grava primeiro no SQLite
/// (offline-first) e depois tenta replicar no Firestore. Se a nuvem não
/// estiver acessível, o registro fica com `sync_status = pending` e é
/// reenviado na próxima sincronização.
class NoteRepository {
  NoteRepository({DatabaseHelper? local, FirestoreService? remote})
    : _local = local ?? DatabaseHelper.instance,
      _remote = remote ?? FirestoreService();

  /// Notas na lixeira há mais tempo que isso são excluídas definitivamente.
  static const Duration trashRetention = Duration(days: 30);

  final DatabaseHelper _local;
  final FirestoreService _remote;
  final Uuid _uuid = const Uuid();

  // ------------------------------------------------------------ consultas

  Future<List<Note>> getNotes(
    String uid, {
    String query = '',
    String? category,
    NoteSort sort = NoteSort.updatedDesc,
  }) {
    return _local.getNotes(uid, query: query, category: category, sort: sort);
  }

  Future<List<Note>> getTrash(String uid) {
    return _local.getNotes(uid, inTrash: true);
  }

  Future<int> countPending(String uid) => _local.countUnsyncedNotes(uid);

  // -------------------------------------------------------------- escrita

  Note newNote({
    required String uid,
    required String title,
    required String content,
    required String category,
  }) {
    final now = DateTime.now().toUtc();
    return Note(
      remoteId: _uuid.v4(),
      uid: uid,
      title: title,
      content: content,
      category: category,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Cria ou atualiza uma nota.
  Future<SaveResult> saveNote(Note note) async {
    final pending = note.copyWith(
      updatedAt: DateTime.now().toUtc(),
      syncStatus: SyncStatus.pending,
    );
    await _local.upsertNote(pending);
    return _push(pending);
  }

  /// Move a nota para a lixeira (exclusão temporária).
  Future<SaveResult> moveToTrash(Note note) {
    final now = DateTime.now().toUtc();
    return saveNote(note.copyWith(isDeleted: true, deletedAt: now));
  }

  /// Recupera uma nota da lixeira.
  Future<SaveResult> restoreFromTrash(Note note) {
    return saveNote(note.copyWith(isDeleted: false, clearDeletedAt: true));
  }

  /// Exclui a nota definitivamente do aparelho e da nuvem.
  Future<SaveResult> deletePermanently(Note note) async {
    final purge = note.copyWith(syncStatus: SyncStatus.pendingPurge);
    await _local.upsertNote(purge);
    return _push(purge);
  }

  Future<SaveResult> emptyTrash(String uid) async {
    SaveResult result = const SaveResult.synced();
    for (final note in await getTrash(uid)) {
      final r = await deletePermanently(note);
      if (!r.syncedToCloud) result = r;
    }
    return result;
  }

  /// Envia uma única alteração ao Firestore.
  Future<SaveResult> _push(Note note) async {
    try {
      if (note.syncStatus == SyncStatus.pendingPurge) {
        await _remote.deleteNote(note.uid, note.remoteId);
        await _local.deleteNote(note.uid, note.remoteId);
      } else {
        await _remote.upsertNote(note);
        await _local.updateNote(note.copyWith(syncStatus: SyncStatus.synced));
      }
      return const SaveResult.synced();
    } catch (e) {
      debugPrint('Falha ao enviar nota ${note.remoteId}: $e');
      return SaveResult.pending(describeSyncError(e));
    }
  }

  // ----------------------------------------------------------- categorias

  /// Categorias do usuário. Na primeira vez cria as categorias padrão.
  Future<List<NoteCategory>> getCategories(String uid) async {
    var categories = await _local.getCategories(uid);
    if (categories.isEmpty) {
      for (final name in NoteCategory.defaults) {
        await _local.insertCategory(_buildCategory(uid, name));
      }
      categories = await _local.getCategories(uid);
    }
    return categories;
  }

  /// Cria uma categoria (ou devolve a existente com o mesmo nome).
  Future<NoteCategory> addCategory(String uid, String name) async {
    final trimmed = name.trim();
    final existing = await _local.getCategoryByName(uid, trimmed);
    if (existing != null) return existing;

    final category = _buildCategory(uid, trimmed);
    await _local.insertCategory(category);
    try {
      await _remote.upsertCategory(category);
      await _local.markCategorySynced(uid, category.remoteId);
    } catch (e) {
      debugPrint('Categoria "$trimmed" ficará pendente: $e');
    }
    return category;
  }

  NoteCategory _buildCategory(String uid, String name) {
    return NoteCategory(
      remoteId: _uuid.v4(),
      uid: uid,
      name: name,
      createdAt: DateTime.now().toUtc(),
    );
  }

  // ------------------------------------------------------- sincronização

  /// Sincronização completa:
  /// 1. envia ao Firestore tudo que está pendente no SQLite;
  /// 2. baixa as notas/categorias da nuvem e mescla com o SQLite;
  /// 3. remove da lixeira as notas com mais de [trashRetention].
  Future<SyncReport> synchronize(String uid) async {
    var pushed = 0;
    var pulled = 0;
    try {
      for (final category in await _local.getUnsyncedCategories(uid)) {
        await _remote.upsertCategory(category);
        await _local.markCategorySynced(uid, category.remoteId);
      }
      for (final note in await _local.getUnsyncedNotes(uid)) {
        final result = await _push(note);
        if (!result.syncedToCloud) {
          return SyncReport(pushed: pushed, error: result.error);
        }
        pushed++;
      }

      for (final category in await _remote.fetchCategories(uid)) {
        if (await _local.getCategoryByName(uid, category.name) == null) {
          await _local.insertCategory(category);
        }
      }

      final remoteNotes = await _remote.fetchNotes(uid);
      final plan = SyncService.merge(
        await _local.getAllNotes(uid),
        remoteNotes,
      );
      for (final note in plan.toInsertLocally) {
        await _local.insertNote(note);
        await _ensureCategory(uid, note.category);
        pulled++;
      }
      for (final note in plan.toUpdateLocally) {
        await _local.updateNote(note);
        await _ensureCategory(uid, note.category);
        pulled++;
      }
      for (final note in plan.toDeleteLocally) {
        await _local.deleteNote(uid, note.remoteId);
        pulled++;
      }

      await _purgeExpiredTrash(uid);
      return SyncReport(pushed: pushed, pulled: pulled);
    } catch (e) {
      debugPrint('Falha na sincronização: $e');
      return SyncReport(
        pushed: pushed,
        pulled: pulled,
        error: describeSyncError(e),
      );
    }
  }

  Future<void> _ensureCategory(String uid, String name) async {
    if (await _local.getCategoryByName(uid, name) == null) {
      await _local.insertCategory(
        _buildCategory(uid, name).copyWith(syncStatus: SyncStatus.synced),
      );
    }
  }

  Future<void> _purgeExpiredTrash(String uid) async {
    final limit = DateTime.now().toUtc().subtract(trashRetention);
    for (final note in await getTrash(uid)) {
      final deletedAt = note.deletedAt;
      if (deletedAt != null && deletedAt.isBefore(limit)) {
        await deletePermanently(note);
      }
    }
  }
}
