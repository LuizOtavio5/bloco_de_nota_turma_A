import 'package:flutter/material.dart';

import '../models/note.dart';

class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback? onTap;

  /// Ações exibidas à direita (ex.: mover para lixeira, restaurar).
  final List<Widget> actions;

  const NoteCard({
    super.key,
    required this.note,
    this.onTap,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final synced = note.syncStatus == SyncStatus.synced;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE5FA),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.notes_rounded,
                  color: Color(0xFF6C4AB6),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title.isEmpty ? 'Sem título' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF292333),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      note.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF77717F),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE5FA),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            note.category,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6C4AB6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            note.date,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9A94A1),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: synced
                              ? 'Sincronizada com a nuvem'
                              : 'Aguardando envio para a nuvem',
                          child: Icon(
                            synced
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_upload_outlined,
                            size: 16,
                            color: synced
                                ? const Color(0xFF4F9A6B)
                                : const Color(0xFFC28A2B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
