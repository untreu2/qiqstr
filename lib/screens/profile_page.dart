import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/note_widget.dart';
import 'package:qiqstr/widgets/profile_info_widget.dart';

class ProfilePage extends StatefulWidget {
  final UserModel user;

  const ProfilePage({super.key, required this.user});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ScrollController _scrollController = ScrollController();
  final SplayTreeSet<NoteModel> _notes = SplayTreeSet(_compareNotes);
  late final DataService _dataService;

  bool _isLoading = true;
  bool _isLoadingOlder = false;

  static int _compareNotes(NoteModel a, NoteModel b) {
    final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
    final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
    final res = bTime.compareTo(aTime);
    return res == 0 ? a.id.compareTo(b.id) : res;
  }

  @override
  void initState() {
    super.initState();
    _dataService = DataService(
      npub: widget.user.npub,
      dataType: DataType.Profile,
      onNewNote: _onNewNote,
    );
    _scrollController.addListener(_onScroll);
    _initialize();
  }

  void _onScroll() {
    if (!_isLoadingOlder &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadOlderNotes();
    }
  }

  Future<void> _initialize() async {
    await _dataService.initialize();
    await _dataService.loadNotesFromCache((cached) => _notes.addAll(cached));
    await _dataService.initializeConnections();
    setState(() => _isLoading = false);
  }

  Future<void> _loadOlderNotes() async {
    setState(() => _isLoadingOlder = true);
    await _dataService.fetchOlderNotes([widget.user.npub], (note) {
      _notes.add(note);
    });
    setState(() => _isLoadingOlder = false);
  }

  void _onNewNote(NoteModel note) {
    if (_notes.add(note)) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dataService.closeConnections();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: ProfileInfoWidget(user: widget.user),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == _notes.length && _isLoadingOlder) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final note = _notes.elementAt(index);
                      return NoteWidget(
                        note: note,
                        dataService: _dataService,
                        reactionCount: 0,
                        replyCount: 0,
                        repostCount: 0,
                      );
                    },
                    childCount: _notes.length + (_isLoadingOlder ? 1 : 0),
                  ),
                ),
              ],
            ),
    );
  }
}
