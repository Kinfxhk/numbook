import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/document.dart';
import '../i18n/strings.dart';
import 'feedback.dart';
import 'theme.dart';

class CommandAction {
  final String id;
  final IconData icon;
  final String label;
  final String? subtitle;
  final String? shortcut;
  final List<String> keywords;
  final VoidCallback onRun;

  const CommandAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onRun,
    this.subtitle,
    this.shortcut,
    this.keywords = const [],
  });
}

/// Offline fuzzy command palette & quick sheet switcher (`⌘K` / `Ctrl+K`).
Future<void> showCommandPalette({
  required BuildContext context,
  required bool dark,
  required String locale,
  required List<CommandAction> actions,
  required List<Sheet> sheets,
  required String? activeSheetId,
  required String? Function(Sheet sheet) folderNameOf,
  required ValueChanged<String> onSelectSheet,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x44000000),
    builder: (_) => _CommandPaletteDialog(
      dark: dark,
      locale: locale,
      actions: actions,
      sheets: sheets,
      activeSheetId: activeSheetId,
      folderNameOf: folderNameOf,
      onSelectSheet: onSelectSheet,
    ),
  );
}

class _PaletteEntry {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badge;
  final bool active;
  final VoidCallback onPick;

  const _PaletteEntry({
    required this.icon,
    required this.title,
    required this.onPick,
    this.subtitle,
    this.badge,
    this.active = false,
  });
}

class _CommandPaletteDialog extends StatefulWidget {
  final bool dark;
  final String locale;
  final List<CommandAction> actions;
  final List<Sheet> sheets;
  final String? activeSheetId;
  final String? Function(Sheet sheet) folderNameOf;
  final ValueChanged<String> onSelectSheet;

  const _CommandPaletteDialog({
    required this.dark,
    required this.locale,
    required this.actions,
    required this.sheets,
    required this.activeSheetId,
    required this.folderNameOf,
    required this.onSelectSheet,
  });

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();
  String _query = '';
  int _selected = 0;

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Substring + ordered character fuzzy match score; 0 means no match.
  int _score(String query, String primary, List<String> extras) {
    if (query.isEmpty) return 1;
    final q = query.toLowerCase();
    final p = primary.toLowerCase();
    if (p == q) return 100;
    if (p.startsWith(q)) return 80;
    if (p.contains(q)) return 60;
    for (final ex in extras) {
      final e = ex.toLowerCase();
      if (e.startsWith(q)) return 50;
      if (e.contains(q)) return 35;
    }
    // Lightweight ordered-subsequence fuzzy match on primary title
    var qi = 0;
    for (var i = 0; i < p.length && qi < q.length; i++) {
      if (p[i] == q[qi]) qi++;
    }
    return qi == q.length ? 20 : 0;
  }

  List<_PaletteEntry> _buildEntries() {
    final q = _query.trim();
    final scored = <(int, _PaletteEntry)>[];

    for (final s in widget.sheets) {
      final title = s.title.isEmpty
          ? T.of(widget.locale, 'untitled')
          : s.title;
      final folder = widget.folderNameOf(s);
      final snippet = s.content
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty && l != '# $title', orElse: () => '');
      final sc = _score(q, title, [?folder, s.content]);
      if (sc > 0) {
        scored.add((
          // When typing a query, sheet matches rank alongside actions; when
          // empty, actions lead and recent sheets follow cleanly.
          q.isEmpty ? 10 : sc + 5,
          _PaletteEntry(
            icon: s.pinned ? Icons.push_pin_outlined : Icons.description_outlined,
            title: title,
            subtitle: [
              if (folder != null && folder.isNotEmpty) folder,
              if (snippet.isNotEmpty) snippet,
            ].join(' · '),
            active: s.id == widget.activeSheetId,
            onPick: () {
              Navigator.of(context).pop();
              widget.onSelectSheet(s.id);
            },
          ),
        ));
      }
    }

    for (final a in widget.actions) {
      final sc = _score(q, a.label, [?a.subtitle, ...a.keywords]);
      if (sc > 0) {
        scored.add((
          q.isEmpty ? 20 : sc,
          _PaletteEntry(
            icon: a.icon,
            title: a.label,
            subtitle: a.subtitle,
            badge: a.shortcut,
            onPick: () {
              Navigator.of(context).pop();
              a.onRun();
            },
          ),
        ));
      }
    }

    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.map((e) => e.$2).toList(growable: false);
  }

  void _moveSelection(int delta, int count) {
    if (count <= 0) return;
    setState(() {
      _selected = (_selected + delta) % count;
      if (_selected < 0) _selected += count;
    });
    if (_scrollController.hasClients) {
      final targetOffset = (_selected * 44.0 - 88.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(targetOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();
    final sel = entries.isEmpty ? 0 : _selected.clamp(0, entries.length - 1);

    return Align(
      alignment: const Alignment(0, -0.45),
      child: Material(
        color: Colors.transparent,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _moveSelection(1, entries.length),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _moveSelection(-1, entries.length),
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (entries.isNotEmpty) {
                tapFeedback();
                entries[sel].onPick();
              }
            },
          },
          child: Container(
            key: const ValueKey('command-palette'),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 420),
            decoration: BoxDecoration(
              color: Palette.bg(widget.dark),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Palette.hairline(widget.dark)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 17,
                        color: Palette.answer(widget.dark),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('command-palette-input'),
                          controller: _queryController,
                          autofocus: true,
                          onChanged: (v) => setState(() {
                            _query = v;
                            _selected = 0;
                          }),
                          onSubmitted: (_) {
                            if (entries.isNotEmpty) {
                              tapFeedback();
                              entries[sel].onPick();
                            }
                          },
                          style: TextStyle(
                            fontSize: 14,
                            color: Palette.fg(widget.dark),
                          ),
                          cursorColor: Palette.answer(widget.dark),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: T.of(widget.locale, 'commandHint'),
                            hintStyle: TextStyle(
                              fontSize: 13.5,
                              color: Palette.faint(widget.dark),
                            ),
                          ),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        Pressable(
                          onTap: () => setState(() {
                            _queryController.clear();
                            _query = '';
                            _selected = 0;
                          }),
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 15,
                            color: Palette.faint(widget.dark),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: Palette.hairline(widget.dark),
                            ),
                          ),
                          child: Text(
                            'ESC',
                            style: TextStyle(
                              fontFamily: monoFamily,
                              fontSize: 10,
                              color: Palette.faint(widget.dark),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Palette.hairline(widget.dark)),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      T.of(widget.locale, 'noMatches'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Palette.faint(widget.dark),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      controller: _scrollController,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: entries.length,
                      itemBuilder: (ctx, i) {
                        final item = entries[i];
                        final chosen = i == sel;
                        return Pressable(
                          onTap: item.onPick,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 42),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: chosen
                                  ? Palette.answer(
                                      widget.dark,
                                    ).withValues(alpha: 0.11)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item.icon,
                                  size: 16,
                                  color: chosen || item.active
                                      ? Palette.answer(widget.dark)
                                      : Palette.faint(widget.dark),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: chosen || item.active
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: Palette.fg(widget.dark),
                                        ),
                                      ),
                                      if (item.subtitle != null &&
                                          item.subtitle!.isNotEmpty)
                                        Text(
                                          item.subtitle!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Palette.faint(widget.dark),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (item.badge != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    item.badge!,
                                    style: TextStyle(
                                      fontFamily: monoFamily,
                                      fontSize: 11,
                                      color: Palette.faint(widget.dark),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
