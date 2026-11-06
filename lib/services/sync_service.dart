import '../models/note.dart';

/// Resultado da comparação entre as notas locais e as da nuvem.
class MergePlan {
  /// Notas da nuvem que não existem no aparelho (ex.: nova instalação).
  final List<Note> toInsertLocally = [];

  /// Notas da nuvem mais recentes que a cópia local.
  final List<Note> toUpdateLocally = [];

  /// Notas locais já sincronizadas que não existem mais na nuvem
  /// (foram excluídas definitivamente em outro aparelho).
  final List<Note> toDeleteLocally = [];

  bool get isEmpty =>
      toInsertLocally.isEmpty &&
      toUpdateLocally.isEmpty &&
      toDeleteLocally.isEmpty;
}

/// Regras de sincronização (sem dependência de Firebase/SQLite, para
/// poderem ser testadas com testes unitários).
class SyncService {
  const SyncService._();

  /// Resolve um conflito entre a versão local e a remota de uma mesma nota
  /// usando a estratégia "última escrita vence" (last-write-wins) pelo
  /// campo `updatedAt`. Em caso de empate, a versão local é mantida.
  static Note resolveConflict(Note local, Note remote) {
    return remote.updatedAt.isAfter(local.updatedAt) ? remote : local;
  }

  /// Compara as notas locais com as da nuvem e decide o que precisa
  /// mudar no SQLite.
  static MergePlan merge(List<Note> localNotes, List<Note> remoteNotes) {
    final plan = MergePlan();
    final localById = {for (final n in localNotes) n.remoteId: n};
    final remoteIds = <String>{};

    for (final remote in remoteNotes) {
      remoteIds.add(remote.remoteId);
      final local = localById[remote.remoteId];

      if (local == null) {
        plan.toInsertLocally.add(remote);
        continue;
      }

      if (local.syncStatus == SyncStatus.synced) {
        if (!remote.updatedAt.isAtSameMomentAs(local.updatedAt) ||
            remote.isDeleted != local.isDeleted) {
          plan.toUpdateLocally.add(remote.copyWith(id: local.id));
        }
        continue;
      }

      // Existe alteração local pendente: decide pelo updatedAt.
      final winner = resolveConflict(local, remote);
      if (identical(winner, remote)) {
        plan.toUpdateLocally.add(remote.copyWith(id: local.id));
      }
    }

    for (final local in localNotes) {
      if (local.syncStatus == SyncStatus.synced &&
          !remoteIds.contains(local.remoteId)) {
        plan.toDeleteLocally.add(local);
      }
    }

    return plan;
  }
}
