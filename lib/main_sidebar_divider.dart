part of 'main.dart';

/// Drag handle between the library sidebar and the editor.
class _SidebarResizeDivider extends StatefulWidget {
  final bool dark;
  final bool dragging;
  final double width;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;
  final VoidCallback onReset;
  final ValueChanged<double> onNudge;

  const _SidebarResizeDivider({
    required this.dark,
    required this.dragging,
    required this.width,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onReset,
    required this.onNudge,
  });

  @override
  State<_SidebarResizeDivider> createState() => _SidebarResizeDividerState();
}

class _SidebarResizeDividerState extends State<_SidebarResizeDivider> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hairline = Palette.hairline(widget.dark);
    const hitW = 10.0;
    return FocusableActionDetector(
      actions: {
        _NudgeSidebarIntent: CallbackAction<_NudgeSidebarIntent>(
          onInvoke: (i) {
            widget.onNudge(i.delta);
            return null;
          },
        ),
        _ResetSidebarIntent: CallbackAction<_ResetSidebarIntent>(
          onInvoke: (_) {
            widget.onReset();
            return null;
          },
        ),
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _NudgeSidebarIntent(-8),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NudgeSidebarIntent(8),
        SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            _NudgeSidebarIntent(-24),
        SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            _NudgeSidebarIntent(24),
        SingleActivator(LogicalKeyboardKey.keyR): _ResetSidebarIntent(),
      },
      child: Semantics(
        label: LocaleScope.t(context, 'sidebarDivider'),
        hint: LocaleScope.t(context, 'sidebarDividerHint'),
        slider: true,
        value: widget.width.toStringAsFixed(0),
        increasedValue: (widget.width + 8).toStringAsFixed(0),
        decreasedValue: (widget.width - 8).toStringAsFixed(0),
        onIncrease: () => widget.onNudge(8),
        onDecrease: () => widget.onNudge(-8),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Tooltip(
            message: LocaleScope.t(context, 'sidebarDividerHint'),
            waitDuration: const Duration(milliseconds: 500),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => widget.onDragStart(),
              onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
              onHorizontalDragEnd: (_) => widget.onDragEnd(),
              onHorizontalDragCancel: widget.onDragCancel,
              onDoubleTap: widget.onReset,
              child: SizedBox(
                width: hitW,
                child: Center(
                  child: Container(
                    width: _hover || widget.dragging ? 2 : 1,
                    color: hairline,
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

class _NudgeSidebarIntent extends Intent {
  final double delta;
  const _NudgeSidebarIntent(this.delta);
}

class _ResetSidebarIntent extends Intent {
  const _ResetSidebarIntent();
}
