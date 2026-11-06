import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/note.dart';
import '../models/note_category.dart';
import '../repositories/note_repository.dart';

class NoteFormPage extends StatefulWidget {
  final Note? note;

  /// Categoria pré-selecionada ao criar uma nota.
  final String? initialCategory;

  const NoteFormPage({super.key, this.note, this.initialCategory});

  @override
  State<NoteFormPage> createState() => _NoteFormPageState();
}

class _NoteFormPageState extends State<NoteFormPage> {
  final titleController = TextEditingController();
  final contentController = TextEditingController();

  final NoteRepository repository = NoteRepository();

  List<NoteCategory> categories = [];
  String selectedCategory = NoteCategory.defaultName;
  bool saving = false;

  bool get isEditing => widget.note != null;

  static const String _newCategoryValue = '__nova_categoria__';

  @override
  void initState() {
    super.initState();

    if (isEditing) {
      titleController.text = widget.note!.title;
      contentController.text = widget.note!.content;
      selectedCategory = widget.note!.category;
    } else if (widget.initialCategory != null) {
      selectedCategory = widget.initialCategory!;
    }
    loadCategories();
  }

  Future<void> loadCategories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final result = await repository.getCategories(user.uid);
    if (mounted) setState(() => categories = result);
  }

  Future<void> createCategory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = await showNewCategoryDialog(context);
    if (name == null || name.isEmpty) return;

    final category = await repository.addCategory(user.uid, name);
    await loadCategories();
    if (mounted) setState(() => selectedCategory = category.name);
  }

  Future<void> saveNote() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final title = titleController.text.trim();
    final content = contentController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escreva o conteúdo da nota.')),
      );
      return;
    }

    setState(() => saving = true);

    final note = isEditing
        ? widget.note!.copyWith(
            title: title,
            content: content,
            category: selectedCategory,
          )
        : repository.newNote(
            uid: user.uid,
            title: title,
            content: content,
            category: selectedCategory,
          );

    final result = await repository.saveNote(note);

    if (mounted) Navigator.pop(context, result);
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = categories.map((c) => c.name).toList();
    if (!names.contains(selectedCategory)) names.add(selectedCategory);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Editar nota' : 'Nova nota',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Salvar',
            onPressed: saving ? null : saveNote,
            icon: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF292333),
              ),
              decoration: const InputDecoration(
                hintText: 'Título',
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.label_outline, color: Color(0xFF6C4AB6)),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(selectedCategory),
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: [
                      for (final name in names)
                        DropdownMenuItem(value: name, child: Text(name)),
                      const DropdownMenuItem(
                        value: _newCategoryValue,
                        child: Text('+ Nova categoria...'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == _newCategoryValue) {
                        createCategory();
                      } else if (value != null) {
                        setState(() => selectedCategory = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(color: Color(0xFFE4DFEA)),
            Expanded(
              child: TextField(
                controller: contentController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.5,
                  color: Color(0xFF40394A),
                ),
                decoration: const InputDecoration(
                  hintText: 'Comece a escrever...',
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo para digitar o nome de uma nova categoria.
Future<String?> showNewCategoryDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nova categoria'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(hintText: 'Ex.: Faculdade'),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Criar'),
        ),
      ],
    ),
  );
}
