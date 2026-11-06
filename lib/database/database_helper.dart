import 'package:bloco_de_nota_turma_a/models/note.dart';
import 'package:bloco_de_nota_turma_a/models/note_category.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Ordenações disponíveis na listagem de notas.
enum NoteSort {
  updatedDesc('Última atualização (recentes)', 'updated_at DESC'),
  updatedAsc('Última atualização (antigas)', 'updated_at ASC'),
  createdDesc('Data de criação (recentes)', 'created_at DESC'),
  createdAsc('Data de criação (antigas)', 'created_at ASC'),
  titleAsc('Título (A-Z)', 'title COLLATE NOCASE ASC');

  const NoteSort(this.label, this.orderBy);

  final String label;
  final String orderBy;
}

/// Acesso ao banco local (SQLite). Implementa o padrão Singleton para
/// que todo o app compartilhe a mesma conexão.
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static const int _version = 2;

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    return _database ??= await _initDB('notes.db');
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return openDatabase(
      path,
      version: _version,
      onCreate: (db, version) => _createTables(db),
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_id TEXT NOT NULL UNIQUE,
        uid TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '${NoteCategory.defaultName}',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute('CREATE INDEX idx_notes_uid ON notes(uid)');

    await db.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_id TEXT NOT NULL UNIQUE,
        uid TEXT NOT NULL,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        UNIQUE(uid, name)
      )
    ''');
  }

  /// Migração da versão 1 (id, uid, title, content, date) para a versão 2.
  /// As notas antigas são copiadas e marcadas como pendentes de envio.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE notes RENAME TO notes_v1');
        await _createTables(txn);

        final oldRows = await txn.query('notes_v1');
        final now = DateTime.now().toUtc();
        for (final row in oldRows) {
          final note = Note(
            remoteId: const Uuid().v4(),
            uid: row['uid'] as String,
            title: row['title'] as String? ?? '',
            content: row['content'] as String? ?? '',
            category: NoteCategory.defaultName,
            createdAt: now,
            updatedAt: now,
          );
          await txn.insert('notes', note.toMap()..remove('id'));
        }
        await txn.execute('DROP TABLE notes_v1');
      });
    }
  }

  // ---------------------------------------------------------------- notas

  Future<int> insertNote(Note note) async {
    final db = await database;
    return db.insert('notes', note.toMap()..remove('id'));
  }

  Future<int> updateNote(Note note) async {
    final db = await database;
    return db.update(
      'notes',
      note.toMap()..remove('id'),
      where: 'remote_id = ? AND uid = ?',
      whereArgs: [note.remoteId, note.uid],
    );
  }

  /// Insere ou substitui a nota usando o `remote_id` como chave.
  Future<void> upsertNote(Note note) async {
    final updated = await updateNote(note);
    if (updated == 0) await insertNote(note);
  }

  Future<Note?> getNoteByRemoteId(String uid, String remoteId) async {
    final db = await database;
    final rows = await db.query(
      'notes',
      where: 'uid = ? AND remote_id = ?',
      whereArgs: [uid, remoteId],
      limit: 1,
    );
    return rows.isEmpty ? null : Note.fromMap(rows.first);
  }

  /// Lista as notas visíveis do usuário, com pesquisa por título/conteúdo,
  /// filtro por categoria e ordenação.
  Future<List<Note>> getNotes(
    String uid, {
    String query = '',
    String? category,
    bool inTrash = false,
    NoteSort sort = NoteSort.updatedDesc,
  }) async {
    final db = await database;

    final where = <String>['uid = ?', 'is_deleted = ?', 'sync_status != ?'];
    final args = <Object>[uid, inTrash ? 1 : 0, SyncStatus.pendingPurge.name];

    final text = query.trim();
    if (text.isNotEmpty) {
      where.add('(title LIKE ? OR content LIKE ?)');
      args
        ..add('%$text%')
        ..add('%$text%');
    }
    if (category != null) {
      where.add('category = ?');
      args.add(category);
    }

    final result = await db.query(
      'notes',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: inTrash ? 'deleted_at DESC' : sort.orderBy,
    );
    return result.map(Note.fromMap).toList();
  }

  /// Todas as notas do usuário, incluindo lixeira e exclusões pendentes.
  /// Usado pela sincronização.
  Future<List<Note>> getAllNotes(String uid) async {
    final db = await database;
    final rows = await db.query('notes', where: 'uid = ?', whereArgs: [uid]);
    return rows.map(Note.fromMap).toList();
  }

  Future<List<Note>> getUnsyncedNotes(String uid) async {
    final db = await database;
    final rows = await db.query(
      'notes',
      where: 'uid = ? AND sync_status != ?',
      whereArgs: [uid, SyncStatus.synced.name],
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<int> countUnsyncedNotes(String uid) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM notes WHERE uid = ? AND sync_status != ?',
      [uid, SyncStatus.synced.name],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<int> deleteNote(String uid, String remoteId) async {
    final db = await database;
    return db.delete(
      'notes',
      where: 'uid = ? AND remote_id = ?',
      whereArgs: [uid, remoteId],
    );
  }

  // ----------------------------------------------------------- categorias

  Future<List<NoteCategory>> getCategories(String uid) async {
    final db = await database;
    final rows = await db.query(
      'categories',
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(NoteCategory.fromMap).toList();
  }

  Future<NoteCategory?> getCategoryByName(String uid, String name) async {
    final db = await database;
    final rows = await db.query(
      'categories',
      where: 'uid = ? AND name = ? COLLATE NOCASE',
      whereArgs: [uid, name],
      limit: 1,
    );
    return rows.isEmpty ? null : NoteCategory.fromMap(rows.first);
  }

  Future<void> insertCategory(NoteCategory category) async {
    final db = await database;
    await db.insert(
      'categories',
      category.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> markCategorySynced(String uid, String remoteId) async {
    final db = await database;
    await db.update(
      'categories',
      {'sync_status': SyncStatus.synced.name},
      where: 'uid = ? AND remote_id = ?',
      whereArgs: [uid, remoteId],
    );
  }

  Future<List<NoteCategory>> getUnsyncedCategories(String uid) async {
    final db = await database;
    final rows = await db.query(
      'categories',
      where: 'uid = ? AND sync_status != ?',
      whereArgs: [uid, SyncStatus.synced.name],
    );
    return rows.map(NoteCategory.fromMap).toList();
  }
}
