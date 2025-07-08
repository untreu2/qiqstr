import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/services/media_service.dart';
import 'package:qiqstr/widgets/note_widget.dart';
import '../colors.dart';

enum NoteLoadingState {
  loading,
  profileLoading,
  mediaLoading,
  ready,
  error,
}

class LazyNoteWidget extends StatefulWidget {
  final NoteModel note;
  final DataService dataService;
  final String currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;
  final Map<String, UserModel> profiles;
  final bool isSmallView;

  const LazyNoteWidget({
    super.key,
    required this.note,
    required this.dataService,
    required this.currentUserNpub,
    required this.notesNotifier,
    required this.profiles,
    this.isSmallView = true,
  });

  @override
  State<LazyNoteWidget> createState() => _LazyNoteWidgetState();
}

class _LazyNoteWidgetState extends State<LazyNoteWidget> {
  NoteLoadingState _loadingState = NoteLoadingState.loading;
  Timer? _timeoutTimer;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _startLoadingProcess();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _updateState(NoteLoadingState newState) {
    if (!_isDisposed && mounted) {
      setState(() {
        _loadingState = newState;
      });
    }
  }

  Future<void> _startLoadingProcess() async {
    _timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (!_isDisposed) {
        _updateState(NoteLoadingState.ready);
      }
    });

    try {
      await _loadProfile();
      if (_isDisposed) return;

      await _loadContent();
      if (_isDisposed) return;

      await _loadMedia();
      if (_isDisposed) return;

      _timeoutTimer?.cancel();
      _updateState(NoteLoadingState.ready);
    } catch (e) {
      if (!_isDisposed) {
        _updateState(NoteLoadingState.error);
      }
    }
  }

  Future<void> _loadProfile() async {
    _updateState(NoteLoadingState.profileLoading);
    
    if (widget.profiles.containsKey(widget.note.author)) {
      return;
    }

    final completer = Completer<void>();
    
    void profileListener() {
      if (widget.dataService.profilesNotifier.value.containsKey(widget.note.author)) {
        widget.dataService.profilesNotifier.removeListener(profileListener);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }
    
    widget.dataService.profilesNotifier.addListener(profileListener);

    await widget.dataService.fetchProfilesBatch([widget.note.author]);
    
    try {
      await completer.future.timeout(const Duration(seconds: 3));
    } catch (e) {
    }
    
    widget.dataService.profilesNotifier.removeListener(profileListener);
  }

  Future<void> _loadContent() async {
    widget.dataService.parseContentForNote(widget.note);
    
    if (!widget.note.hasMedia) {
      return;
    }
  }

  Future<void> _loadMedia() async {
    if (!widget.note.hasMedia) return;
    
    _updateState(NoteLoadingState.mediaLoading);
    
    final parsed = widget.note.parsedContent;
    if (parsed == null) return;
    
    final mediaUrls = List<String>.from(parsed['mediaUrls'] ?? []);
    if (mediaUrls.isEmpty) return;

    final imageUrls = mediaUrls.where((url) {
      final lower = url.toLowerCase();
      return lower.endsWith('.jpg') ||
             lower.endsWith('.jpeg') ||
             lower.endsWith('.png') ||
             lower.endsWith('.webp') ||
             lower.endsWith('.gif');
    }).toList();

    if (imageUrls.isNotEmpty) {
      final mediaService = MediaService();
      mediaService.preloadCriticalImages(imageUrls);
      
      await _waitForImagesLoad(imageUrls.take(2).toList());
    }
  }

  Future<void> _waitForImagesLoad(List<String> imageUrls) async {
    if (imageUrls.isEmpty) return;
    
    final futures = imageUrls.map((url) => _preloadSingleImage(url)).toList();
    
    try {
      await Future.wait(futures, eagerError: false).timeout(
        const Duration(seconds: 2),
        onTimeout: () => [],
      );
    } catch (e) {
    }
  }

  Future<void> _preloadSingleImage(String url) async {
    try {
      final imageProvider = CachedNetworkImageProvider(url);
      final completer = Completer<void>();
      
      final imageStream = imageProvider.resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      
      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        onError: (exception, stackTrace) {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      imageStream.addListener(listener);
      
      await completer.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
      
      imageStream.removeListener(listener);
    } catch (e) {
    }
  }

  Widget _buildLoadingWidget() {
    String loadingText;
    IconData loadingIcon;
    
    switch (_loadingState) {
      case NoteLoadingState.loading:
        loadingText = 'Loading note...';
        loadingIcon = Icons.notes;
        break;
      case NoteLoadingState.profileLoading:
        loadingText = 'Loading profile...';
        loadingIcon = Icons.person;
        break;
      case NoteLoadingState.mediaLoading:
        loadingText = 'Loading media...';
        loadingIcon = Icons.image;
        break;
      case NoteLoadingState.error:
        loadingText = 'Loading failed';
        loadingIcon = Icons.error_outline;
        break;
      case NoteLoadingState.ready:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                _loadingState == NoteLoadingState.error 
                    ? AppColors.error.withOpacity(0.7)
                    : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            loadingIcon,
            size: 16,
            color: _loadingState == NoteLoadingState.error 
                ? AppColors.error.withOpacity(0.7)
                : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            loadingText,
            style: TextStyle(
              color: _loadingState == NoteLoadingState.error 
                  ? AppColors.error.withOpacity(0.7)
                  : AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingState != NoteLoadingState.ready) {
      return _buildLoadingWidget();
    }

    return NoteWidget(
      key: ValueKey(widget.note.id),
      note: widget.note,
      reactionCount: widget.note.reactionCount,
      replyCount: widget.note.replyCount,
      repostCount: widget.note.repostCount,
      dataService: widget.dataService,
      currentUserNpub: widget.currentUserNpub,
      notesNotifier: widget.notesNotifier,
      profiles: widget.profiles,
      isSmallView: widget.isSmallView,
    );
  }
}