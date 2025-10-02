import 'package:flutter/material.dart';
import '../../models/note_model.dart';

class LazyScrollList extends StatefulWidget {
  final List<NoteModel> items;
  final Widget Function(BuildContext context, NoteModel item, int index) itemBuilder;
  final double estimatedItemHeight;
  final int visibleItemBuffer;
  final ScrollController? controller;
  final void Function()? onLoadMore;
  final bool isLoading;

  const LazyScrollList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.estimatedItemHeight = 200.0,
    this.visibleItemBuffer = 5,
    this.controller,
    this.onLoadMore,
    this.isLoading = false,
  });

  @override
  State<LazyScrollList> createState() => _LazyScrollListState();
}

class _LazyScrollListState extends State<LazyScrollList> {
  late ScrollController _scrollController;
  final Map<int, double> _itemHeights = {};
  final Map<int, GlobalKey> _itemKeys = {};

  int _firstVisibleIndex = 0;
  int _lastVisibleIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateVisibleRange();
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _scrollController.dispose();
    } else {
      _scrollController.removeListener(_onScroll);
    }
    super.dispose();
  }

  void _onScroll() {
    _updateVisibleRange();

    if (widget.onLoadMore != null && !widget.isLoading) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;

      if (currentScroll >= maxScroll * 0.8) {
        widget.onLoadMore!();
      }
    }
  }

  void _updateVisibleRange() {
    if (!mounted || widget.items.isEmpty) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final scrollOffset = _scrollController.offset;

    int firstIndex = _estimateIndexAtOffset(scrollOffset);
    int lastIndex = _estimateIndexAtOffset(scrollOffset + viewportHeight);

    firstIndex = (firstIndex - widget.visibleItemBuffer).clamp(0, widget.items.length - 1);
    lastIndex = (lastIndex + widget.visibleItemBuffer).clamp(0, widget.items.length - 1);

    if (firstIndex != _firstVisibleIndex || lastIndex != _lastVisibleIndex) {
      setState(() {
        _firstVisibleIndex = firstIndex;
        _lastVisibleIndex = lastIndex;
      });
    }
  }

  int _estimateIndexAtOffset(double offset) {
    if (offset <= 0) return 0;

    double currentOffset = 0;
    for (int i = 0; i < widget.items.length; i++) {
      final height = _getItemHeight(i);
      if (currentOffset + height > offset) {
        return i;
      }
      currentOffset += height;
    }

    return widget.items.length - 1;
  }

  double _getItemHeight(int index) {
    return _itemHeights[index] ?? widget.estimatedItemHeight;
  }

  void _measureItem(int index) {
    final key = _itemKeys[index];
    if (key?.currentContext != null) {
      final renderBox = key!.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final height = renderBox.size.height;
        if (_itemHeights[index] != height) {
          _itemHeights[index] = height;

          if (widget.items[index].estimatedHeight != height) {
            widget.items[index].estimatedHeight = height;
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Text('No items to display'),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < _firstVisibleIndex || index > _lastVisibleIndex) {
            return SizedBox(height: _getItemHeight(index));
          }

          _itemKeys[index] = GlobalKey();

          return _MeasuredItem(
            key: _itemKeys[index],
            onMeasured: () => _measureItem(index),
            child: widget.itemBuilder(context, widget.items[index], index),
          );
        },
        childCount: widget.items.length + (widget.isLoading ? 1 : 0),
      ),
    );
  }
}

class _MeasuredItem extends StatefulWidget {
  final Widget child;
  final VoidCallback onMeasured;

  const _MeasuredItem({
    super.key,
    required this.child,
    required this.onMeasured,
  });

  @override
  State<_MeasuredItem> createState() => _MeasuredItemState();
}

class _MeasuredItemState extends State<_MeasuredItem> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMeasured();
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class LazyNotesList extends StatelessWidget {
  final List<NoteModel> notes;
  final Widget Function(BuildContext context, NoteModel note, int index) itemBuilder;
  final ScrollController? controller;
  final void Function()? onLoadMore;
  final bool isLoading;

  const LazyNotesList({
    super.key,
    required this.notes,
    required this.itemBuilder,
    this.controller,
    this.onLoadMore,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      slivers: [
        LazyScrollList(
          items: notes,
          itemBuilder: itemBuilder,
          estimatedItemHeight: 180.0,
          visibleItemBuffer: 3,
          onLoadMore: onLoadMore,
          isLoading: isLoading,
        ),
        if (isLoading)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );
  }
}
