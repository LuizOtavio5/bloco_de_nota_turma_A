import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/note.dart';
import '../repositories/note_repository.dart';
import '../widgets/note_card.dart';

/// Lixeira: notas excluídas temporariamente, que podem ser recuperadas
/// ou excluídas definitivamente (do aparelho e do Firestore).
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  final NoteRepository repository = NoteRepository();
  List<Note> notes = [];

  String get uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    loadTrash();
  }

  Future<void> loadTrash() async {
    final result = await repository.getTrash(uid);
    if (mounted) setState(() => notes = result);
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> restore(Note note) async {
    final result = await repository.restoreFromTrash(note);
    await loadTrash();
    showMessage(
      result.syncedToCloud
          ? 'Nota recuperada.'
          : 'Nota recuperada no aparelho. ${result.error ?? ''}',
    );
  }

  Future<bool> confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir definitivamente?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> deleteForever(Note note) async {
    if (!await confirm('Esta nota não poderá ser recuperada.')) return;
    final result = await repository.deletePermanently(note);
    await loadTrash();
    showMessage(
      result.syncedToCloud
          ? 'Nota excluída definitivamente.'
          : 'Excluída no aparelho; a exclusão na nuvem está pendente.',
    );
  }

  Future<void> emptyTrash() async {
    if (!await confirm('Todas as notas da lixeira serão apagadas.')) return;
    final result = await repository.emptyTrash(uid);
    await loadTrash();
    showMessage(
      result.syncedToCloud
          ? 'Lixeira esvaziada.'
          : 'Lixeira esvaziada no aparelho; exclusões na nuvem pendentes.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Lixeira',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (notes.isNotEmpty)
            TextButton.icon(
              onPressed: emptyTrash,
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Esvaziar'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notas na lixeira são excluídas automaticamente após '
              '${NoteRepository.trashRetention.inDays} dias.',
              style: const TextStyle(color: Color(0xFF77717F), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: notes.isEmpty
                  ? const Center(child: Text('A lixeira está vazia.'))
                  : ListView.builder(
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return NoteCard(
                          note: note,
                          actions: [
                            IconButton(
                              tooltip: 'Recuperar',
                              onPressed: () => restore(note),
                              icon: const Icon(
                                Icons.restore_rounded,
                                color: Color(0xFF4F9A6B),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Excluir definitivamente',
                              onPressed: () => deleteForever(note),
                              icon: const Icon(
                                Icons.delete_forever_outlined,
                                color: Color(0xFFB45F6C),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
