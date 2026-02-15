import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/theme_manager.dart';

class AppPopupMenuItem {
  final String value;
  final IconData icon;
  final String label;

  const AppPopupMenuItem({
    required this.value,
    required this.icon,
    required this.label,
  });
}

class AppPopupMenuButton extends StatefulWidget {
  final List<AppPopupMenuItem> items;
  final ValueChanged<String> onSelected;
  final Widget child;

  const AppPopupMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    required this.child,
  });

  @override
  State<AppPopupMenuButton> createState() => _AppPopupMenuButtonState();
}

class _AppPopupMenuButtonState extends State<AppPopupMenuButton> {
  final GlobalKey _anchorKey = GlobalKey();

  List<PopupMenuEntry<String>> _buildEntries() {
    final dividerColor = context.colors.background.withValues(alpha: 0.4);
    final entries = <PopupMenuEntry<String>>[];

    for (var i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      entries.add(
        PopupMenuItem<String>(
          value: item.value,
          padding: EdgeInsets.zero,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(item.icon, size: 17, color: context.colors.background),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: context.colors.background,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (i < widget.items.length - 1) {
        entries.add(PopupMenuDivider(height: 1));
        entries.add(
          PopupMenuItem<String>(
            enabled: false,
            height: 0,
            padding: EdgeInsets.zero,
            child:             Divider(
              height: 1,
              thickness: 0.5,
              color: dividerColor,
            ),
          ),
        );
      }
    }

    return entries;
  }

  void _show() {
    HapticFeedback.lightImpact();
    final RenderBox? renderBox =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final entries = _buildEntries();

    final screenHeight = MediaQuery.of(context).size.height;
    final estimatedMenuHeight = widget.items.length * 56.0;
    final spaceBelow = screenHeight - (offset.dy + size.height);
    final openAbove = spaceBelow < estimatedMenuHeight + 140;

    final RelativeRect menuPosition;
    if (openAbove) {
      menuPosition = RelativeRect.fromLTRB(
        offset.dx,
        offset.dy - estimatedMenuHeight - size.height,
        offset.dx + size.width,
        offset.dy - size.height,
      );
    } else {
      menuPosition = RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy + size.height + estimatedMenuHeight,
      );
    }

    showMenu<String>(
      context: context,
      position: menuPosition,
      color: context.colors.textPrimary,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      items: entries,
    ).then((value) {
      if (value == null) return;
      HapticFeedback.lightImpact();
      widget.onSelected(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _anchorKey,
      onTap: _show,
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}
