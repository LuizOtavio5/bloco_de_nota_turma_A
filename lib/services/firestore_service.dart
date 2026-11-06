import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/note.dart';
import '../models/note_category.dart';

/// Fonte de dados remota (Cloud Firestore).
///
/// Estrutura no Firestore:
///   users/{uid}/notes/{remoteId}
///   users/{uid}/categories/{remoteId}
///
/// Todas as operações têm tempo limite: sem conexão, o Firestore apenas
/// enfileira a escrita e o Future nunca completa, então o tempo limite é o
/// que permite ao app perceber a falha e manter a alteração como pendente.
class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const Duration timeout = Duration(seconds: 10);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _notes(String uid) =>
      _firestore.collection('users').doc(uid).collection('notes');

  CollectionReference<Map<String, dynamic>> _categories(String uid) =>
      _firestore.collection('users').doc(uid).collection('categories');

  Future<void> upsertNote(Note note) {
    return _notes(
      note.uid,
    ).doc(note.remoteId).set(note.toFirestore()).timeout(timeout);
  }

  Future<void> deleteNote(String uid, String remoteId) {
    return _notes(uid).doc(remoteId).delete().timeout(timeout);
  }

  Future<List<Note>> fetchNotes(String uid) async {
    final snapshot = await _notes(
      uid,
    ).get(const GetOptions(source: Source.server)).timeout(timeout);
    return snapshot.docs
        .map((doc) => Note.fromFirestore(doc.id, doc.data()))
        .toList();
  }

  Future<void> upsertCategory(NoteCategory category) {
    return _categories(
      category.uid,
    ).doc(category.remoteId).set(category.toFirestore()).timeout(timeout);
  }

  Future<List<NoteCategory>> fetchCategories(String uid) async {
    final snapshot = await _categories(
      uid,
    ).get(const GetOptions(source: Source.server)).timeout(timeout);
    return snapshot.docs
        .map((doc) => NoteCategory.fromFirestore(doc.id, doc.data()))
        .toList();
  }
}
