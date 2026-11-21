import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/document.dart';
import 'data/rates.dart';
import 'engine/engine.dart';
import 'engine/values.dart';
import 'i18n/strings.dart';
import 'io/document_io.dart';
import 'io/file_actions.dart';
import 'ui/command_palette.dart';
import 'ui/editor_pane.dart';
import 'ui/feedback.dart';
import 'ui/formatting.dart';
import 'ui/key_bar.dart';
import 'ui/settings_sheet.dart';
import 'ui/sidebar.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TallynoteApp());
}

class TallynoteApp extends StatefulWidget {
  const TallynoteApp({super.key});

  @override
  State<TallynoteApp> createState() => _AppState();
}

class _AppState extends State<TallynoteApp> with WidgetsBindingObserver {
  final _store = DocumentStore();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _navKey = GlobalKey<NavigatorState>();
  final _fileBtnKey = GlobalKey();

  late PaneState _paneA;

  /// Non-null while the split is on: the second editor.
  PaneState? _paneB;
  bool _focusB = false;

  /// Set while the app itself adds the split's second sheet: that store
  /// notification must not move the new sheet into the first pane too.
  bool _routingOwn = false;

  bool _dark = false;
  String _themeMode = 'light';
  bool _haptics = true;
  bool _sidebarOpen = true;
  bool _answersVisible = true;
  bool _autoRates = true;
  bool _steps = true;
  bool _keyBar = true;
  double _answerW = 212;
  bool _answerWSet = false;
  double _splitRatio = 0.5;
  double _uiScale = 1.0;
  String? _locale;
  String _numberPreset = 'us';
  String _yenCode = 'JPY';
  bool _lineNumbers = true;
  bool _showTabs = true;
  final List<String> _tabs = [];

  final ValueNotifier<bool> _zoomModifier = ValueNotifier(false);
  bool _zoomHud = false;
  bool _savedFlash = false;
  final FocusNode _searchFocus = FocusNode();
  Timer? _zoomHudTimer;

  bool get _split => _paneB != null;
  PaneState get _focused => (_focusB && _paneB != null) ? _paneB! : _paneA;
  List<PaneState> get _livePanes => [_paneA, ?_paneB];

  bool _onKey(KeyEvent e) {
    final down =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (_zoomModifier.value != down) _zoomModifier.value = down;
    return false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_zoomModifier.value) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _zoom(dy < 0 ? 1.1 : 1 / 1.1);
    });
  }

  bool _signColours = true;
  String _posName = '';
  String _negName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _paneA = _newPane('');
    unawaited(_boot());
  }

  PaneState _newPane(String sheetId) {
    final pane = PaneState(
      store: _store,
      sheetId: sheetId,
      makeEngine: _makeEngine,
      answerW: _answerW,
      explicitW: _answerWSet,
    )..addListener(_onPane);
    pane.load(sheetId);
    return pane;
  }

  void _onPane() {
    if (mounted) setState(() {});
  }

  SheetEngine _makeEngine() => SheetEngine(
    rates: Rates.current,
    format: NumberFormat.ofPreset(_numberPreset, yen: _yenCode),
  );

  Future<void> _boot() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode =
        prefs.getString('tallynote.theme') ??
        (defaultTargetPlatform == TargetPlatform.android
            ? 'system'
            : ((prefs.getBool('tallynote.dark') ?? false) ? 'dark' : 'light'));
    _haptics = prefs.getBool('tallynote.haptics') ?? true;
    Haptics.on = _haptics;
    _answersVisible = prefs.getBool('tallynote.answers') ?? true;
    _autoRates = prefs.getBool('tallynote.autoRates') ?? true;
    _steps = prefs.getBool('tallynote.steps') ?? true;
    _keyBar = prefs.getBool('tallynote.keyBar') ?? true;
    _answerW = prefs.getDouble('tallynote.answerWidth') ?? 212;
    _answerWSet = prefs.getBool('tallynote.answerWidthSet') ?? false;
    for (final p in _livePanes) {
      p.adoptWidth(_answerW, _answerWSet);
    }
    _splitRatio = prefs.getDouble('tallynote.splitRatio') ?? 0.5;
    _uiScale = prefs.getDouble('tallynote.uiScale') ?? 1.0;
    _locale = prefs.getString('tallynote.locale');
    _numberPreset = prefs.getString('tallynote.numberFormat') ?? 'us';
    _yenCode = prefs.getString('tallynote.yen') ?? 'JPY';
    _lineNumbers = prefs.getBool('tallynote.lineNumbers') ?? true;
    _showTabs = prefs.getBool('tallynote.showTabs') ?? true;
    _signColours = prefs.getBool('tallynote.signColours') ?? true;
    _posName = prefs.getString('tallynote.posColour') ?? '';
    _negName = prefs.getString('tallynote.negColour') ?? '';
    final splitOn = prefs.getBool('tallynote.split') ?? false;
    final splitSheet = prefs.getString('tallynote.splitSheet') ?? '';
    final splitFirst = prefs.getString('tallynote.splitPrimary') ?? '';

    await _store.load();
    _store.addListener(_onStore);
    final first =
        splitOn &&
            splitFirst != splitSheet &&
            _store.sheets.any((s) => s.id == splitFirst)
        ? splitFirst
        : _store.activeId!;
    _paneA.load(first);
    if (splitOn) _restoreSplit(splitSheet);
    _focusB = _paneB != null && _store.activeId == _paneB!.sheetId;
    await Rates.load(allowNetwork: _autoRates);
    for (final p in _livePanes) {
      p.rebuildEngine();
    }
    if (!mounted) return;
    setState(() {});
  }

  void _restoreSplit(String stored) {
    final active = _paneA.sheetId;
    if (_store.sheets.length < 2) return;
    final known =
        stored.isNotEmpty &&
        stored != active &&
        _store.sheets.any((s) => s.id == stored);
    final second = known
        ? stored
        : _store.sheets.firstWhere((s) => s.id != active).id;
    _paneB = _newPane(second);
  }

  void _onStore() {
    if (!mounted) return;
    final id = _store.activeId;
    if (id != null && !_tabs.contains(id)) _tabs.add(id);
    if (_tabs.length > 8) _tabs.removeAt(0);
    _syncPanes();
    setState(() {});
  }

  void _syncPanes() {
    if (_routingOwn) return;
    final ids = _store.sheets.map((s) => s.id).toSet();
    String other(String not) =>
        ids.firstWhere((id) => id != not, orElse: () => '');

    final b = _paneB;
    if (b != null &&
        (!ids.contains(b.sheetId) || b.sheetId == _paneA.sheetId)) {
      final take = other(_paneA.sheetId);
      if (take.isEmpty) {
        _closeSplit();
      } else {
        b.load(take);
      }
    }
    if (!ids.contains(_paneA.sheetId)) {
      final active = _store.activeId ?? '';
      final take = ids.contains(active) && active != _paneB?.sheetId
          ? active
          : other(_paneB?.sheetId ?? '');
      if (take.isEmpty) {
        _closeSplit();
        return;
      }
      _paneA.load(take);
    }

    final id = _store.activeId;
    if (id == null || id == _focused.sheetId) return;
    if (_paneB != null && id == _paneB!.sheetId) {
      _focusB = true;
    } else if (_paneB != null && id == _paneA.sheetId) {
      _focusB = false;
    } else {
      _focused.load(id);
    }
  }

  void _activate(String id) {
    final b = _paneB;
    if (b != null && id == b.sheetId) {
      setState(() => _focusB = true);
    } else {
      if (b != null && id == _paneA.sheetId) setState(() => _focusB = false);
      _focused.load(id);
    }
    _store.select(id);
    if (_split) _saveSettings();
  }

  void _focusPane(PaneState p) {
    if (_paneB == null) return;
    final moved = _focusB != (p == _paneB);
    final reselect = _store.activeId != p.sheetId;
    if (!moved && !reselect) return;
    setState(() => _focusB = p == _paneB);
    if (reselect) _store.select(p.sheetId);
    _saveSettings();
  }

  void _toggleSplit() {
    tapFeedback(light: true);
    if (_split) {
      _closeSplit();
      return;
    }
    final other = _store.sheets
        .where((s) => s.id != _paneA.sheetId)
        .firstOrNull;
    if (other != null) {
      setState(() => _paneB = _newPane(other.id));
    } else {
      _routingOwn = true;
      final s = _store.create();
      _routingOwn = false;
      setState(() {
        _paneB = _newPane(s.id);
        _focusB = true;
      });
    }
    _saveSettings();
  }

  void _closeSplit() {
    final b = _paneB;
    if (b == null) return;
    b.flush();
    final active = _store.activeId;
    setState(() {
      _paneB = null;
      _focusB = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!b.disposed) b.dispose();
    });
    if (active != null && active != _paneA.sheetId) _paneA.load(active);
    _saveSettings();
  }

  bool get _backStacked =>
      _focused.hasSelection ||
      (_scaffoldKey.currentState?.isDrawerOpen ?? false) ||
      _split ||
      _focused.focus.hasFocus;

  void _back() {
    if (_focused.hasSelection) {
      final c = _focused.controller;
      setState(() {
        c.selection = TextSelection.collapsed(offset: c.selection.extentOffset);
      });
      return;
    }
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen ?? false) {
      scaffold!.closeDrawer();
      return;
    }
    if (_split) {
      _closeSplit();
      return;
    }
    if (_focused.focus.hasFocus) _focused.focus.unfocus();
  }

  void _closeTab(String id) {
    _tabs.remove(id);
    if (_store.activeId == id && _tabs.isNotEmpty) _store.select(_tabs.last);
    setState(() {});
  }

  void _zoom(double factor) => _setScale((_uiScale * factor).clamp(0.75, 2.5));

  void _setScale(double v) {
    setState(() {
      _uiScale = v.clamp(0.75, 2.5);
      _zoomHud = true;
    });
    _zoomHudTimer?.cancel();
    _zoomHudTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _zoomHud = false);
    });
    _saveSettings();
  }

  @override
  void didChangePlatformBrightness() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flush();
  }

  void _flush() {
    for (final p in _livePanes) {
      p.flush();
    }
  }

  Future<void> _fileMenu() async {
    final navCtx = _navKey.currentContext!;
    final l = LocaleScope.of(navCtx);
    String t(String k) => T.of(l, k);
    final entries = <(String?, String)>[
      ('new', t('fileNew')),
      ('open', t('fileOpen')),
      ('copy', t('fileSaveCopy')),
      (null, ''),
      ('md', t('exportMd')),
      ('csv', t('exportCsv')),
      ('txt', t('exportTxt')),
      ('print', t('filePrint')),
    ];

    String? choice;
    if (MediaQuery.sizeOf(navCtx).width < 700) {
      choice = await showModalBottomSheet<String>(
        context: navCtx,
        backgroundColor: Palette.bg(_dark),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (value, label) in entries)
                if (value == null)
                  Divider(height: 8, color: Palette.hairline(_dark))
                else
                  Pressable(
                    onTap: () => Navigator.pop(ctx, value),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              color: Palette.fg(_dark),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      );
    } else {
      var rect = const RelativeRect.fromLTRB(60, 48, 0, 0);
      final btnBox = _fileBtnKey.currentContext?.findRenderObject();
      final overlayBox = Overlay.maybeOf(navCtx)?.context.findRenderObject();
      if (btnBox is RenderBox && overlayBox is RenderBox) {
        final topLeft = btnBox.localToGlobal(Offset.zero, ancestor: overlayBox);
        final bottomRight = btnBox.localToGlobal(
          btnBox.size.bottomRight(Offset.zero),
          ancestor: overlayBox,
        );
        rect = RelativeRect.fromRect(
          Rect.fromPoints(
            Offset(topLeft.dx, bottomRight.dy),
            Offset(bottomRight.dx, bottomRight.dy),
          ),
          Offset.zero & overlayBox.size,
        );
      }
      choice = await showMenu<String>(
        context: navCtx,
        position: rect,
        color: Palette.bg(_dark),
        items: [
          for (final (value, label) in entries)
            if (value == null)
              const PopupMenuDivider()
            else
              PopupMenuItem(value: value, child: Text(label)),
        ],
      );
    }
    await _runFileChoice(choice);
  }

  Future<void> _runFileChoice(String? choice) async {
    switch (choice) {
      case 'new':
        _store.create();
      case 'open':
        await _openFromFile();
      case 'copy':
        await _saveCopy();
      case 'md' || 'csv' || 'txt':
        await _exportAs(choice!);
      case 'print':
        await _print();
    }
  }

  void _copyToast(String text) {
    Clipboard.setData(ClipboardData(text: text));
    final navCtx = _navKey.currentContext;
    if (navCtx == null) return;
    final l = LocaleScope.of(navCtx);
    ScaffoldMessenger.maybeOf(navCtx)?.showSnackBar(
      SnackBar(
        content: Text(T.of(l, 'copied')),
        duration: const Duration(milliseconds: 1100),
      ),
    );
  }

  void _copyActiveSheetMarkdown() {
    final s = _focused.sheet;
    if (s == null) return;
    final live = Sheet(
      id: s.id,
      title: s.title,
      content: _focused.contentToSave,
      folderId: s.folderId,
    );
    _copyToast(DocumentIo.singleSheetMarkdown(live, _makeEngine()));
  }

  Future<void> _openSettings({int initialTab = 0}) => showSettingsSheet(
    context: _navKey.currentContext!,
    dark: _dark,
    themeMode: _themeMode,
    answersVisible: _answersVisible,
    autoRates: _autoRates,
    steps: _steps,
    signColours: _signColours,
    lineNumbers: _lineNumbers,
    showTabs: _showTabs,
    uiScale: _uiScale,
    locale: _locale ?? _effectiveLocale,
    numberPreset: _numberPreset,
    yenCode: _yenCode,
    initialTab: initialTab,
    onLocale: (v) {
      setState(() => _locale = v);
      _saveSettings();
    },
    onNumberPreset: (v) {
      setState(() => _numberPreset = v);
      for (final p in _livePanes) {
        p.rebuildEngine();
      }
      _saveSettings();
    },
    onYenCode: (v) {
      setState(() => _yenCode = v);
      for (final p in _livePanes) {
        p.rebuildEngine();
      }
      _saveSettings();
    },
    onInsertCheatExample: (example) {
      final c = _focused.controller;
      final base = c.text;
      final sep = base.isEmpty || base.endsWith('\n') ? '' : '\n';
      final next = '$base$sep$example';
      c.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    },
    posName: _posName,
    negName: _negName,
    onAnswers: (v) {
      setState(() => _answersVisible = v);
      _saveSettings();
    },
    onThemeMode: (v) {
      setState(() => _themeMode = v);
      _saveSettings();
    },
    haptics: _haptics,
    onHaptics: (v) {
      Haptics.on = v;
      setState(() => _haptics = v);
      _saveSettings();
    },
    onAutoRates: (v) {
      setState(() => _autoRates = v);
      _saveSettings();
    },
    onSteps: (v) {
      setState(() => _steps = v);
      _saveSettings();
    },
    keyBar: _keyBar,
    onKeyBar: (v) {
      setState(() => _keyBar = v);
      _saveSettings();
    },
    onSignColours: (v) {
      setState(() => _signColours = v);
      _saveSettings();
    },
    onPosColour: (name) {
      setState(() => _posName = name);
      _saveSettings();
    },
    onNegColour: (name) {
      setState(() => _negName = name);
      _saveSettings();
    },
    onLineNumbers: (v) {
      setState(() => _lineNumbers = v);
      _saveSettings();
    },
    onShowTabs: (v) {
      setState(() => _showTabs = v);
      _saveSettings();
    },
    onUiScale: (v) {
      setState(() => _uiScale = v);
      _saveSettings();
    },
    onRefreshRates: () async {
      final ok = await Rates.refresh();
      if (!mounted) return false;
      for (final p in _livePanes) {
        p.rebuildEngine();
      }
      return ok;
    },
  );

  Future<void> _openCommandPalette() async {
    final navCtx = _navKey.currentContext;
    if (navCtx == null) return;
    final l = LocaleScope.of(navCtx);
    String t(String k) => T.of(l, k);
    final total = _focused.sheetTotalDisplay;
    final allAnswers = _focused.results
        .map((r) => r.display)
        .whereType<String>()
        .toList();

    final actions = <CommandAction>[
      CommandAction(
        id: 'new-sheet',
        icon: Icons.add,
        label: t('newSheet'),
        shortcut: '⌘N',
        keywords: const ['new', 'create', 'sheet', 'note'],
        onRun: () => _store.create(),
      ),
      if (total != null)
        CommandAction(
          id: 'copy-total',
          icon: Icons.functions,
          label: '${t('copyGrandTotal')} ($total)',
          keywords: const ['total', 'sum', 'copy', 'grand'],
          onRun: () => _copyToast(total),
        ),
      if (allAnswers.isNotEmpty)
        CommandAction(
          id: 'copy-answers',
          icon: Icons.content_copy,
          label: t('copyAllAnswers'),
          keywords: const ['copy', 'answers', 'results'],
          onRun: () => _copyToast(allAnswers.join('\n')),
        ),
      CommandAction(
        id: 'copy-sheet-md',
        icon: Icons.description_outlined,
        label: t('copySheetMd'),
        shortcut: '⌘⇧C',
        keywords: const ['copy', 'markdown', 'md', 'share', 'note'],
        onRun: _copyActiveSheetMarkdown,
      ),
      CommandAction(
        id: 'toggle-split',
        icon: Icons.vertical_split,
        label: _split ? t('unsplit') : t('split'),
        shortcut: '⌘⇧\\',
        keywords: const ['split', 'dual', 'pane', 'side'],
        onRun: _toggleSplit,
      ),
      CommandAction(
        id: 'toggle-sidebar',
        icon: Icons.view_sidebar_outlined,
        label: t('sidebar'),
        shortcut: '⌘\\',
        keywords: const ['sidebar', 'folders', 'drawer'],
        onRun: _toggleSidebar,
      ),
      CommandAction(
        id: 'toggle-answers',
        icon: Icons.visibility_outlined,
        label: t('answers'),
        shortcut: '⌘⇧A',
        keywords: const ['answers', 'hide', 'show', 'column'],
        onRun: () {
          setState(() => _answersVisible = !_answersVisible);
          _saveSettings();
        },
      ),
      CommandAction(
        id: 'toggle-theme',
        icon: _dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        label: '${t('theme')}: ${_dark ? t('light') : t('dark')}',
        keywords: const ['dark', 'light', 'theme', 'mode'],
        onRun: () {
          setState(() => _themeMode = _dark ? 'light' : 'dark');
          _saveSettings();
        },
      ),
      CommandAction(
        id: 'toggle-numformat',
        icon: Icons.pin_outlined,
        label:
            '${t('switchNumberFormat')} (${_numberPreset.toUpperCase()} → ${_numberPreset == 'us' ? 'EU' : 'US'})',
        keywords: const ['number', 'format', 'eu', 'us', 'comma', 'decimal'],
        onRun: () {
          setState(
            () => _numberPreset = _numberPreset == 'us' ? 'eu' : 'us',
          );
          for (final p in _livePanes) {
            p.rebuildEngine();
          }
          _saveSettings();
        },
      ),
      CommandAction(
        id: 'export-md',
        icon: Icons.file_download_outlined,
        label: t('exportMd'),
        keywords: const ['export', 'markdown', 'md'],
        onRun: () => _exportAs('md'),
      ),
      CommandAction(
        id: 'export-csv',
        icon: Icons.table_chart_outlined,
        label: t('exportCsv'),
        keywords: const ['export', 'csv', 'excel', 'spreadsheet'],
        onRun: () => _exportAs('csv'),
      ),
      CommandAction(
        id: 'save-copy',
        icon: Icons.save_alt,
        label: t('fileSaveCopy'),
        shortcut: '⌘⇧D',
        keywords: const ['backup', 'save', 'json', 'copy'],
        onRun: _saveCopy,
      ),
      CommandAction(
        id: 'print',
        icon: Icons.print_outlined,
        label: t('filePrint'),
        keywords: const ['print', 'pdf'],
        onRun: _print,
      ),
      CommandAction(
        id: 'cheat-sheet',
        icon: Icons.menu_book_outlined,
        label: t('cheatSheet'),
        keywords: const ['help', 'cheat', 'syntax', 'examples', 'reference'],
        onRun: () => _openSettings(initialTab: 3),
      ),
      CommandAction(
        id: 'settings',
        icon: Icons.tune,
        label: t('settings'),
        keywords: const ['settings', 'preferences', 'language'],
        onRun: _openSettings,
      ),
    ];

    await showCommandPalette(
      context: navCtx,
      dark: _dark,
      locale: l,
      actions: actions,
      sheets: _store.sheets,
      activeSheetId: _focused.sheetId,
      folderNameOf: (s) => _store.folderOf(s)?.name,
      onSelectSheet: _activate,
    );
  }

  Future<void> _renameActiveSheet() async {
    final navCtx = _navKey.currentContext;
    final s = _focused.sheet;
    if (navCtx == null || s == null) return;
    final locale = LocaleScope.of(navCtx);
    final c = TextEditingController(
      text: s.title.isEmpty ? T.of(locale, 'untitled') : s.title,
    );
    final res = await showDialog<String>(
      context: navCtx,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.bg(_dark),
        title: Text(
          T.of(locale, 'renameSheet'),
          style: TextStyle(fontSize: 15, color: Palette.fg(_dark)),
        ),
        content: TextField(
          controller: c,
          autofocus: true,
          style: TextStyle(color: Palette.fg(_dark)),
          decoration: InputDecoration(hintText: T.of(locale, 'name')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              T.of(locale, 'cancel'),
              style: TextStyle(color: Palette.faint(_dark)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(
              T.of(locale, 'ok'),
              style: TextStyle(color: Palette.answer(_dark)),
            ),
          ),
        ],
      ),
    );
    c.dispose();
    final trimmed = (res ?? '').trim();
    if (trimmed.isNotEmpty) _store.rename(s.id, trimmed);
  }

  // ---- file verbs ---------------------------------------------------------

  Future<void> _openFromFile() async {
    final messenger = ScaffoldMessenger.of(_navKey.currentContext!);
    final l = LocaleScope.of(_navKey.currentContext!);
    try {
      final raw = await FileActions.openDocument();
      if (raw == null) return;
      final parsed = DocumentIo.parse(raw);
      final n = _store.importSheets(parsed.sheets, parsed.folders);
      messenger.showSnackBar(
        SnackBar(content: Text(T.format(l, 'imported', {'n': '$n'}))),
      );
    } on FormatException {
      messenger.showSnackBar(SnackBar(content: Text(T.of(l, 'notTallynote'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open: $e')));
    }
  }

  Future<void> _saveCopy() async {
    final messenger = ScaffoldMessenger.of(_navKey.currentContext!);
    final l = LocaleScope.of(_navKey.currentContext!);
    final now = DateTime.now();
    final name = DocumentIo.fileName(
      _store.active?.title ?? 'tallynote',
      now,
      DocumentIo.fileExtension,
    );
    final ok = await FileActions.saveAs(
      fileName: name,
      content: DocumentIo.libraryJson(_store.sheets, _store.folders, now: now),
      extension: DocumentIo.fileExtension,
    );
    if (ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(T.format(l, 'savedAs', {'name': name}))),
      );
    }
  }

  Future<void> _exportAs(String kind) async {
    final messenger = ScaffoldMessenger.of(_navKey.currentContext!);
    final l = LocaleScope.of(_navKey.currentContext!);
    final now = DateTime.now();
    final base = _store.active?.title ?? 'tallynote';
    final engine = _makeEngine();
    final sheets = _store.sheets;
    final (content, ext) = switch (kind) {
      'md' => (DocumentIo.markdown(sheets, engine), 'md'),
      'csv' => (DocumentIo.csv(sheets, engine), 'csv'),
      _ => (DocumentIo.plainText(sheets, engine), 'txt'),
    };
    final name = DocumentIo.fileName(base, now, ext);
    final ok = await FileActions.saveAs(
      fileName: name,
      content: content,
      extension: ext,
    );
    if (ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(T.format(l, 'savedAs', {'name': name}))),
      );
    }
  }

  Future<void> _print() async {
    final messenger = ScaffoldMessenger.of(_navKey.currentContext!);
    try {
      await FileActions.printSheets(_store.sheets, _makeEngine());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not print: $e')));
    }
  }

  void _saveNow() {
    for (final p in _livePanes) {
      p.saveNow();
    }
    setState(() => _savedFlash = true);
    Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _savedFlash = false);
    });
  }

  void _focusSearch() {
    if (!_sidebarOpen) setState(() => _sidebarOpen = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _store.removeListener(_onStore);
    for (final p in _livePanes) {
      p.dispose();
    }
    _zoomModifier.dispose();
    _searchFocus.dispose();
    _store.dispose();
    super.dispose();
  }

  void _toggleSidebar() => setState(() => _sidebarOpen = !_sidebarOpen);

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tallynote.theme', _themeMode);
    await prefs.setBool('tallynote.haptics', _haptics);
    await prefs.setBool('tallynote.answers', _answersVisible);
    await prefs.setBool('tallynote.autoRates', _autoRates);
    await prefs.setBool('tallynote.steps', _steps);
    await prefs.setBool('tallynote.keyBar', _keyBar);
    await prefs.setDouble('tallynote.answerWidth', _answerW);
    await prefs.setBool('tallynote.answerWidthSet', _answerWSet);
    await prefs.setDouble('tallynote.splitRatio', _splitRatio);
    await prefs.setDouble('tallynote.uiScale', _uiScale);
    if (_locale != null) await prefs.setString('tallynote.locale', _locale!);
    await prefs.setString('tallynote.numberFormat', _numberPreset);
    await prefs.setString('tallynote.yen', _yenCode);
    await prefs.setBool('tallynote.lineNumbers', _lineNumbers);
    await prefs.setBool('tallynote.showTabs', _showTabs);
    await prefs.setBool('tallynote.signColours', _signColours);
    await prefs.setString('tallynote.posColour', _posName);
    await prefs.setString('tallynote.negColour', _negName);
    await prefs.setBool('tallynote.split', _split);
    await prefs.setString('tallynote.splitSheet', _paneB?.sheetId ?? '');
    await prefs.setString(
      'tallynote.splitPrimary',
      _paneB == null ? '' : _paneA.sheetId,
    );
  }

  String get _effectiveLocale {
    final chosen = _locale;
    if (chosen != null) return chosen;
    final sys = WidgetsBinding.instance.platformDispatcher.locale;
    if (sys.languageCode == 'zh') {
      return sys.scriptCode == 'Hans' || sys.countryCode == 'CN'
          ? 'zh_Hans'
          : 'zh_Hant';
    }
    if (sys.languageCode == 'ja') return 'ja';
    if (sys.languageCode == 'ko') return 'ko';
    return 'en';
  }

  Locale get _materialLocale => switch (_effectiveLocale) {
    'zh_Hant' => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    ),
    'zh_Hans' => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hans',
    ),
    'ja' => const Locale('ja'),
    'ko' => const Locale('ko'),
    _ => const Locale('en'),
  };

  void _format(String open, String close) => _focused.format(open, close);

  Widget _panesView(double width) {
    final b = _paneB;
    if (b == null) {
      return _pane(_paneA, focused: true, showTitle: false);
    }
    final top = _pane(_paneA, focused: !_focusB, showTitle: true);
    final bottom = _pane(
      b,
      focused: _focusB,
      showTitle: true,
      onUnsplit: _closeSplit,
    );
    final each = (width - _SplitDivider.hit) / 2;
    final side = width >= 1000 || (width >= 700 && each >= 340);

    return LayoutBuilder(
      builder: (context, box) {
        final total = (side ? box.maxWidth : box.maxHeight) - _SplitDivider.hit;
        final first = (total * _splitRatio).clamp(0.0, total);
        final handle = _SplitDivider(
          dark: _dark,
          vertical: !side,
          onDrag: (dx) => setState(
            () => _splitRatio = (_splitRatio + dx / total).clamp(0.15, 0.85),
          ),
          onDragEnd: _saveSettings,
          onReset: () {
            setState(() => _splitRatio = 0.5);
            _saveSettings();
          },
          onSwap: _swapPanes,
        );
        if (!side) {
          return Column(
            key: const ValueKey('split-column'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: first, child: top),
              handle,
              Expanded(child: bottom),
            ],
          );
        }
        return Row(
          key: const ValueKey('split-row'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: first, child: top),
            handle,
            Expanded(child: bottom),
          ],
        );
      },
    );
  }

  void _swapPanes() {
    final b = _paneB;
    if (b == null) return;
    tapFeedback(light: true);
    setState(() {
      _paneB = _paneA;
      _paneA = b;
      _focusB = !_focusB;
    });
    _saveSettings();
  }

  Widget _pane(
    PaneState p, {
    required bool focused,
    required bool showTitle,
    VoidCallback? onUnsplit,
  }) => EditorPane(
    pane: p,
    dark: _dark,
    focused: focused,
    showTitle: showTitle,
    otherSheetId: (p == _paneA ? _paneB : _paneA)?.sheetId,
    answersVisible: _answersVisible,
    showSteps: _steps,
    showLineNumbers: _lineNumbers,
    signColours: _signColours,
    positiveColour: _posName.isEmpty ? null : Fmt.colours[_posName],
    negativeColour: _negName.isEmpty ? null : Fmt.colours[_negName],
    wheelBlocked: _zoomModifier,
    onUnsplit: onUnsplit,
    onFocus: () => _focusPane(p),
    onPickSheet: _activate,
    onAnswerWidth: (w) {
      _answerW = w;
      _answerWSet = true;
      _saveSettings();
    },
  );

  @override
  Widget build(BuildContext context) {
    _dark = switch (_themeMode) {
      'system' =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
      'dark' => true,
      _ => false,
    };
    for (final p in _livePanes) {
      p.controller.dark = _dark;
      p.applyLabels();
    }
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final media = MediaQuery.of(context);
    final tabsRow = _showTabs && _tabs.length > 1;
    final editorRoom =
        media.size.height -
        media.padding.top -
        media.padding.bottom -
        media.viewInsets.bottom -
        46 -
        26 -
        (tabsRow ? 30 : 0);
    final showKeyBar =
        _keyBar && (media.viewInsets.bottom == 0 || editorRoom - 44 >= 120);
    final theme = buildTheme(_dark);

    final sidebar = Sidebar(
      store: _store,
      dark: _dark,
      wheelBlocked: _zoomModifier,
      searchFocus: _searchFocus,
      onClose: wide ? _toggleSidebar : () => Navigator.of(context).maybePop(),
    );

    final activeSheet = _focused.sheet;
    final activeTitle = activeSheet == null || activeSheet.title.isEmpty
        ? T.of(_effectiveLocale, 'untitled')
        : activeSheet.title;

    return MaterialApp(
      title: 'Numbook',
      debugShowCheckedModeBanner: false,
      locale: _materialLocale,
      supportedLocales: const [
        Locale('en'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        Locale('ja'),
        Locale('ko'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final s = _uiScale;
        if ((s - 1).abs() < 0.01) {
          return LocaleScope(locale: _effectiveLocale, child: child);
        }
        final mq = MediaQuery.of(context);
        final logical = mq.size / s;
        return LocaleScope(
          locale: _effectiveLocale,
          child: ColoredBox(
            color: Palette.bg(_dark),
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: logical.width,
                maxWidth: logical.width,
                minHeight: logical.height,
                maxHeight: logical.height,
                child: Transform.scale(
                  key: const ValueKey('ui-zoom'),
                  scale: s,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: logical.width,
                    height: logical.height,
                    child: MediaQuery(
                      data: mq.copyWith(
                        size: logical,
                        padding: mq.padding / s,
                        viewPadding: mq.viewPadding / s,
                        viewInsets: mq.viewInsets / s,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      navigatorKey: _navKey,
      theme: theme,
      home: PopScope(
        canPop: !_backStacked,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                _openCommandPalette,
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                _openCommandPalette,
            const SingleActivator(
              LogicalKeyboardKey.keyC,
              meta: true,
              shift: true,
            ): _copyActiveSheetMarkdown,
            const SingleActivator(
              LogicalKeyboardKey.keyC,
              control: true,
              shift: true,
            ): _copyActiveSheetMarkdown,
            const SingleActivator(LogicalKeyboardKey.equal, meta: true): () =>
                _zoom(1.25),
            const SingleActivator(LogicalKeyboardKey.equal, control: true):
                () => _zoom(1.25),
            const SingleActivator(LogicalKeyboardKey.minus, meta: true): () =>
                _zoom(0.8),
            const SingleActivator(LogicalKeyboardKey.minus, control: true):
                () => _zoom(0.8),
            const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () {
              setState(() => _uiScale = 1.0);
              _saveSettings();
            },
            const SingleActivator(LogicalKeyboardKey.digit0, control: true):
                () {
                  setState(() => _uiScale = 1.0);
                  _saveSettings();
                },
            const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
                _saveNow,
            const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                _saveNow,
            const SingleActivator(
              LogicalKeyboardKey.keyD,
              meta: true,
              shift: true,
            ): () {
              final id = _store.activeId;
              if (id != null) _store.duplicate(id);
            },
            const SingleActivator(
              LogicalKeyboardKey.keyD,
              control: true,
              shift: true,
            ): () {
              final id = _store.activeId;
              if (id != null) _store.duplicate(id);
            },
            const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
                _format('**', '**'),
            const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
                _format('**', '**'),
            const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
                _format('_', '_'),
            const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
                _format('_', '_'),
            const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () =>
                _format('__', '__'),
            const SingleActivator(LogicalKeyboardKey.keyU, control: true): () =>
                _format('__', '__'),
            const SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
              shift: true,
            ): () => _format('~~', '~~'),
            const SingleActivator(
              LogicalKeyboardKey.keyS,
              control: true,
              shift: true,
            ): () => _format('~~', '~~'),
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                _focusSearch,
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _focusSearch,
            const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () {
              final id = _store.activeId;
              if (id != null) _closeTab(id);
            },
            const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
              final id = _store.activeId;
              if (id != null) _closeTab(id);
            },
            const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
                _store.create(),
            const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
                _store.create(),
            const SingleActivator(LogicalKeyboardKey.backslash, meta: true):
                _toggleSidebar,
            const SingleActivator(LogicalKeyboardKey.backslash, control: true):
                _toggleSidebar,
            const SingleActivator(
              LogicalKeyboardKey.backslash,
              meta: true,
              shift: true,
            ): _toggleSplit,
            const SingleActivator(
              LogicalKeyboardKey.backslash,
              control: true,
              shift: true,
            ): _toggleSplit,
            const SingleActivator(
              LogicalKeyboardKey.keyA,
              meta: true,
              shift: true,
            ): () {
              setState(() => _answersVisible = !_answersVisible);
              _saveSettings();
            },
            const SingleActivator(
              LogicalKeyboardKey.keyA,
              control: true,
              shift: true,
            ): () {
              setState(() => _answersVisible = !_answersVisible);
              _saveSettings();
            },
          },
          child: Focus(
            autofocus: true,
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: Scaffold(
                key: _scaffoldKey,
                drawer: wide ? null : Drawer(child: SafeArea(child: sidebar)),
                body: SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wide && _sidebarOpen) ...[
                        sidebar,
                        VerticalDivider(
                          width: 1,
                          color: Palette.hairline(_dark),
                        ),
                      ],
                      Expanded(
                        child: Column(
                          children: [
                            _Header(
                              dark: _dark,
                              sidebarOpen: _sidebarOpen && wide,
                              showMenu: !(wide && _sidebarOpen),
                              split: _split,
                              activeTitle: !(wide && _sidebarOpen) && !_split
                                  ? activeTitle
                                  : null,
                              fileBtnKey: _fileBtnKey,
                              onRenameTitle: _renameActiveSheet,
                              onCommandPalette: _openCommandPalette,
                              onSplit: _toggleSplit,
                              onMenu: wide
                                  ? _toggleSidebar
                                  : () =>
                                        _scaffoldKey.currentState?.openDrawer(),
                              onFile: _fileMenu,
                              onSettings: _openSettings,
                            ),
                            Divider(height: 1, color: Palette.hairline(_dark)),
                            if (tabsRow)
                              _TabBar(
                                dark: _dark,
                                tabs: _tabs,
                                activeId: _store.activeId,
                                titleOf: (id) {
                                  final s = _store.sheets
                                      .where((x) => x.id == id)
                                      .firstOrNull;
                                  final navCtx = _navKey.currentContext;
                                  final locale = navCtx == null
                                      ? LocaleScope.of(context)
                                      : LocaleScope.of(navCtx);
                                  return s == null || s.title.isEmpty
                                      ? T.of(locale, 'untitled')
                                      : s.title;
                                },
                                onSelect: _store.select,
                                onClose: _closeTab,
                              ),
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: LayoutBuilder(
                                      builder: (context, box) =>
                                          _panesView(box.maxWidth),
                                    ),
                                  ),
                                  if (_zoomHud)
                                    Positioned(
                                      right: 18,
                                      bottom: 18,
                                      child: _ZoomHud(
                                        dark: _dark,
                                        scale: _uiScale,
                                        onMinus: () => _zoom(1 / 1.1),
                                        onPlus: () => _zoom(1.1),
                                        onReset: () => _setScale(1.0),
                                      ),
                                    ),
                                  if (_focused.hasSelection)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 14,
                                      child: Center(
                                        child: _FormatBar(
                                          dark: _dark,
                                          onFormat: _format,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            _StatusBar(
                              dark: _dark,
                              dirty: _focused.dirty,
                              justSaved: _savedFlash,
                              saveFailed: _store.saveFailed,
                              savedAt: _focused.lastSaved,
                              lines:
                                  _focused.controller.text.split('\n').length,
                              answers: _focused.results
                                  .where((r) => r.display != null)
                                  .length,
                              selectionSummary: _focused.selectionSummary,
                              onCopyValue: _copyToast,
                              onSave: _saveNow,
                            ),
                            if (showKeyBar && _focused.focus.hasFocus)
                              _KeyboardSlot(
                                child: KeyBar(
                                  controller: _focused.controller,
                                  dark: _dark,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _SplitDivider extends StatelessWidget {
  static const hit = 15.0;

  final bool dark;
  final bool vertical;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;
  final VoidCallback onSwap;

  const _SplitDivider({
    required this.dark,
    required this.vertical,
    required this.onDrag,
    required this.onDragEnd,
    required this.onReset,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final line = vertical
        ? Container(height: 1, color: Palette.hairline(dark))
        : Container(width: 1, color: Palette.hairline(dark));
    return MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const ValueKey('split-divider'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: vertical ? null : (d) => onDrag(d.delta.dx),
        onVerticalDragUpdate: vertical ? (d) => onDrag(d.delta.dy) : null,
        onHorizontalDragEnd: vertical ? null : (_) => onDragEnd(),
        onVerticalDragEnd: vertical ? (_) => onDragEnd() : null,
        onDoubleTap: onReset,
        onLongPress: onSwap,
        child: vertical
            ? SizedBox(
                height: hit,
                width: double.infinity,
                child: Center(child: line),
              )
            : SizedBox(
                width: hit,
                height: double.infinity,
                child: Center(child: line),
              ),
      ),
    );
  }
}

class _KeyboardSlot extends StatefulWidget {
  final Widget child;

  const _KeyboardSlot({required this.child});

  @override
  State<_KeyboardSlot> createState() => _KeyboardSlotState();
}

class _KeyboardSlotState extends State<_KeyboardSlot>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => setState(() {});

  @override
  Widget build(BuildContext context) => View.of(context).viewInsets.bottom > 0
      ? widget.child
      : const SizedBox.shrink();
}

class _Header extends StatelessWidget {
  final bool dark;
  final bool sidebarOpen;
  final bool showMenu;
  final bool split;
  final String? activeTitle;
  final Key? fileBtnKey;
  final VoidCallback onMenu;
  final VoidCallback onRenameTitle;
  final VoidCallback onCommandPalette;
  final VoidCallback onSplit;
  final VoidCallback onFile;
  final VoidCallback onSettings;

  const _Header({
    required this.dark,
    required this.sidebarOpen,
    required this.showMenu,
    required this.split,
    required this.onMenu,
    required this.onRenameTitle,
    required this.onCommandPalette,
    required this.onSplit,
    required this.onFile,
    required this.onSettings,
    this.activeTitle,
    this.fileBtnKey,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (showMenu)
              IconButton(
                iconSize: 18,
                tooltip: '${LocaleScope.t(context, 'sheets')}  ⌘\\',
                onPressed: onMenu,
                icon: Icon(Icons.menu, color: Palette.faint(dark)),
              ),
            if (activeTitle != null)
              Expanded(
                child: Pressable(
                  onTap: onRenameTitle,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: Text(
                    activeTitle!,
                    key: const ValueKey('header-sheet-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Palette.fg(dark).withValues(alpha: 0.85),
                    ),
                  ),
                ),
              )
            else
              const Spacer(),
            _IconAction(
              key: const ValueKey('header-command-palette'),
              icon: Icons.terminal,
              tooltip: '${LocaleScope.t(context, 'commandPalette')}  ⌘K',
              dark: dark,
              onTap: onCommandPalette,
            ),
            _IconAction(
              key: fileBtnKey,
              icon: Icons.folder_open_outlined,
              tooltip: LocaleScope.t(context, 'file'),
              dark: dark,
              onTap: onFile,
            ),
            _IconAction(
              icon: Icons.vertical_split,
              tooltip: '${LocaleScope.t(context, 'split')}  ⌘⇧\\',
              dark: dark,
              active: split,
              onTap: onSplit,
            ),
            _IconAction(
              icon: Icons.tune,
              tooltip: LocaleScope.t(context, 'settings'),
              dark: dark,
              onTap: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool dark;
  final bool active;
  final VoidCallback onTap;

  const _IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.dark,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: 17,
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: active ? Palette.fg(dark) : Palette.faint(dark)),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final bool dark;
  final int lines;
  final int answers;
  final bool dirty;
  final bool justSaved;
  final bool saveFailed;
  final DateTime? savedAt;
  final (int count, String sum)? selectionSummary;
  final ValueChanged<String> onCopyValue;
  final VoidCallback onSave;

  const _StatusBar({
    required this.dark,
    required this.lines,
    required this.answers,
    required this.dirty,
    required this.justSaved,
    required this.saveFailed,
    required this.savedAt,
    required this.onCopyValue,
    required this.onSave,
    this.selectionSummary,
  });

  String _saveLabelFor(String locale) {
    if (saveFailed) return T.of(locale, 'saveFailed');
    if (dirty) return T.of(locale, 'editing');
    if (justSaved) return T.of(locale, 'justSaved');
    final at = savedAt;
    if (at == null) return '';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    final sameDay =
        at.year == DateTime.now().year &&
        at.month == DateTime.now().month &&
        at.day == DateTime.now().day;
    final time = '$hh:$mm';
    return sameDay
        ? T.format(locale, 'savedAt', {'time': time})
        : T.format(locale, 'savedOn', {
            'date': '${at.day}/${at.month}',
            'time': time,
          });
  }

  bool _isRateStale() {
    final d = Rates.updatedDate;
    if (d == null) return false;
    final parsed = DateTime.tryParse(d);
    if (parsed == null) return false;
    return DateTime.now().difference(parsed).inDays > 7;
  }

  @override
  Widget build(BuildContext context) {
    final locale = LocaleScope.of(context);
    final rateDate = Rates.updatedDate ?? T.of(locale, 'ratesBuiltIn');
    final stale = _isRateStale();
    final sel = selectionSummary;

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Palette.hairline(dark))),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              T.format(locale, 'linesAnswers', {
                'lines': '$lines',
                'answers': '$answers',
              }),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Palette.faint(dark)),
            ),
          ),
          if (sel != null) ...[
            const SizedBox(width: 12),
            Pressable(
              onTap: () => onCopyValue(sel.$2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                T.format(locale, 'selectionSum', {
                  'n': '${sel.$1}',
                  'sum': sel.$2,
                }),
                key: const ValueKey('status-selection-sum'),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: Palette.answer(dark),
                ),
              ),
            ),
          ],
          const SizedBox(width: 12),
          if (_saveLabelFor(locale).isNotEmpty) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSave,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _saveLabelFor(locale),
                  style: TextStyle(
                    fontSize: 11,
                    color: justSaved
                        ? Palette.positive(dark)
                        : Palette.faint(dark),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          const Spacer(),
          if (stale) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: Palette.answer(dark).withValues(alpha: 0.75),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              T.format(locale, 'rates', {'date': rateDate}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: Palette.faint(dark)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatBar extends StatelessWidget {
  final bool dark;
  final void Function(String open, String close) onFormat;

  const _FormatBar({required this.dark, required this.onFormat});

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, TextStyle style, String open, String close) =>
        Pressable(
          onTap: () => onFormat(open, close),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Text(label, style: style.copyWith(color: Palette.fg(dark))),
          ),
        );

    final base = TextStyle(fontSize: 13, fontFamily: monoFamily);
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: Palette.bg(dark),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Palette.hairline(dark)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(
          children: [
            const SizedBox(width: 8),
            btn('B', base.copyWith(fontWeight: FontWeight.w700), '**', '**'),
            btn('I', base.copyWith(fontStyle: FontStyle.italic), '_', '_'),
            btn(
              'S',
              base.copyWith(decoration: TextDecoration.lineThrough),
              '~~',
              '~~',
            ),
            btn(
              'U',
              base.copyWith(decoration: TextDecoration.underline),
              '__',
              '__',
            ),
            const SizedBox(width: 6),
            for (final entry in Fmt.colours.entries)
              Pressable(
                onTap: () => onFormat('{${entry.key}}', '{/}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 9,
                  ),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: entry.value,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final bool dark;
  final List<String> tabs;
  final String? activeId;
  final String Function(String id) titleOf;
  final void Function(String id) onSelect;
  final void Function(String id) onClose;

  const _TabBar({
    required this.dark,
    required this.tabs,
    required this.activeId,
    required this.titleOf,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.hairline(dark))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final id in tabs)
            Pressable(
              onTap: () => onSelect(id),
              padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
              child: Row(
                children: [
                  Text(
                    titleOf(id),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: id == activeId
                          ? Palette.fg(dark)
                          : Palette.faint(dark),
                    ),
                  ),
                  Pressable(
                    onTap: () => onClose(id),
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.close,
                      size: 11,
                      color: Palette.faint(dark),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoomHud extends StatelessWidget {
  final bool dark;
  final double scale;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onReset;

  const _ZoomHud({
    required this.dark,
    required this.scale,
    required this.onMinus,
    required this.onPlus,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final locale = LocaleScope.of(context);
    Widget button(IconData icon, String tip, VoidCallback tap) => Pressable(
      onTap: tap,
      padding: const EdgeInsets.all(7),
      child: Tooltip(
        message: tip,
        child: Icon(icon, size: 15, color: Palette.fg(dark)),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Palette.bg(dark),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Palette.hairline(dark)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(Icons.remove, '${T.of(locale, 'zoomOut')}  ⌘−', onMinus),
            SizedBox(
              width: 46,
              child: Text(
                '${(scale * 100).round()}%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontFeatures: const [],
                  color: Palette.fg(dark),
                ),
              ),
            ),
            button(Icons.add, '${T.of(locale, 'zoomIn')}  ⌘=', onPlus),
            Container(width: 1, height: 16, color: Palette.hairline(dark)),
            button(
              Icons.restart_alt,
              '${T.of(locale, 'zoomReset')}  ⌘0',
              onReset,
            ),
          ],
        ),
      ),
    );
  }
}
