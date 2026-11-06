import 'dart:async';

import 'package:bloco_de_nota_turma_a/database/database_helper.dart';
import 'package:bloco_de_nota_turma_a/models/note.dart';
import 'package:bloco_de_nota_turma_a/models/note_category.dart';
import 'package:bloco_de_nota_turma_a/pages/login_page.dart';
import 'package:bloco_de_nota_turma_a/pages/note_form_page.dart';
import 'package:bloco_de_nota_turma_a/pages/trash_page.dart';
import 'package:bloco_de_nota_turma_a/repositories/note_repository.dart';
import 'package:bloco_de_nota_turma_a/services/auth_service.dart';
import 'package:bloco_de_nota_turma_a/widgets/note_card.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final NoteRepository repository = NoteRepository();
  final AuthService authService = AuthService();
  final searchController = TextEditingController();

  List<Note> notes = [];
  List<NoteCategory> categories = [];

  String? selectedCategory;
  NoteSort sort = NoteSort.updatedDesc;

  bool syncing = false;
  String? syncError;
  int pendingCount = 0;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    loadNotes().then((_) => synchronize(showResult: false));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  /// Lê as notas do SQLite aplicando pesquisa, categoria e ordenação.
  Future<void> loadNotes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final results = await Future.wait([
      repository.getNotes(
        user.uid,
        query: searchController.text,
        category: selectedCategory,
        sort: sort,
      ),
      repository.getCategories(user.uid),
    ]);
    final pending = await repository.countPending(user.uid);

    if (mounted) {
      setState(() {
        notes = results[0] as List<Note>;
        categories = results[1] as List<NoteCategory>;
        pendingCount = pending;
      });
    }
  }

  /// Envia pendências e baixa as notas do Firestore.
  Future<void> synchronize({bool showResult = true}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || syncing) return;

    setState(() => syncing = true);
    final report = await repository.synchronize(user.uid);
    if (!mounted) return;
    setState(() {
      syncing = false;
      syncError = report.error;
    });
    await loadNotes();

    if (!report.success) {
      showMessage('Modo offline: ${report.error}');
    } else if (showResult) {
      showMessage(
        'Sincronizado. Enviadas: ${report.pushed} · Recebidas: ${report.pulled}',
      );
    }
  }

  void showMessage(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  void onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), loadNotes);
  }

  Future<void> moveToTrash(Note note) async {
    final result = await repository.moveToTrash(note);
    await loadNotes();
    if (!mounted) return;
    showMessage(
      result.syncedToCloud
          ? 'Nota movida para a lixeira.'
          : 'Nota movida para a lixeira (envio à nuvem pendente).',
      action: SnackBarAction(
        label: 'Desfazer',
        onPressed: () async {
          final current = await DatabaseHelper.instance.getNoteByRemoteId(
            note.uid,
            note.remoteId,
          );
          if (current != null) await repository.restoreFromTrash(current);
          await loadNotes();
        },
      ),
    );
  }

  Future<void> logout() async {
    await authService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> openForm({Note? note}) async {
    final result = await Navigator.push<SaveResult>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NoteFormPage(note: note, initialCategory: selectedCategory),
      ),
    );
    await loadNotes();
    if (result != null && mounted) showMessage(result.message);
  }

  Future<void> openTrash() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TrashPage()),
    );
    await loadNotes();
  }

  Future<void> createCategory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final name = await showNewCategoryDialog(context);
    if (name == null || name.isEmpty) return;
    final category = await repository.addCategory(user.uid, name);
    selectedCategory = category.name;
    await loadNotes();
  }

  Widget buildSyncButton() {
    if (syncing) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final offline = syncError != null;
    return IconButton(
      tooltip: offline
          ? 'Offline: $syncError\nToque para tentar novamente'
          : pendingCount > 0
          ? '$pendingCount alteração(ões) pendente(s)'
          : 'Sincronizar com a nuvem',
      onPressed: synchronize,
      icon: Badge(
        isLabelVisible: pendingCount > 0,
        label: Text('$pendingCount'),
        child: Icon(
          offline ? Icons.cloud_off_rounded : Icons.cloud_sync_rounded,
          color: offline ? const Color(0xFFB45F6C) : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final searching = searchController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Minhas notas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          buildSyncButton(),
          PopupMenuButton<NoteSort>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.sort_rounded),
            initialValue: sort,
            onSelected: (value) {
              sort = value;
              loadNotes();
            },
            itemBuilder: (_) => [
              for (final option in NoteSort.values)
                PopupMenuItem(value: option, child: Text(option.label)),
            ],
          ),
          IconButton(
            tooltip: 'Lixeira',
            onPressed: openTrash,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: logout,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openForm(),
        backgroundColor: const Color(0xff6c4ab6),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Nova Nota',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: synchronize,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.email ?? '',
                style: const TextStyle(color: Color(0xFF77717f), fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Pesquisar por título ou conteúdo',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: searching
                      ? IconButton(
                          tooltip: 'Limpar pesquisa',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            searchController.clear();
                            loadNotes();
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('Todas'),
                        selected: selectedCategory == null,
                        onSelected: (_) {
                          selectedCategory = null;
                          loadNotes();
                        },
                      ),
                    ),
                    for (final category in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(category.name),
                          selected: selectedCategory == category.name,
                          onSelected: (_) {
                            selectedCategory = category.name;
                            loadNotes();
                          },
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Categoria'),
                      onPressed: createCategory,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (searching)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${notes.length} resultado(s) para "${searchController.text.trim()}"',
                    style: const TextStyle(
                      color: Color(0xFF77717f),
                      fontSize: 13,
                    ),
                  ),
                ),
              Expanded(
                child: notes.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 60),
                          Center(
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: const BoxDecoration(
                                color: Color(0xffede5fa),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                searching
                                    ? Icons.search_off_rounded
                                    : Icons.sticky_note_2_rounded,
                                size: 42,
                                color: const Color(0xff6c4ab6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 25),
                          Center(
                            child: Text(
                              searching
                                  ? 'Nenhuma nota encontrada'
                                  : 'Nenhuma nota ainda',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              searching
                                  ? 'Tente outro termo de pesquisa.'
                                  : 'Crie sua primeira nota.',
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: notes.length,
                        itemBuilder: (context, index) {
                          final note = notes[index];
                          return NoteCard(
                            note: note,
                            onTap: () => openForm(note: note),
                            actions: [
                              IconButton(
                                tooltip: 'Mover para a lixeira',
                                onPressed: () => moveToTrash(note),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
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
      ),
    );
  }
}
