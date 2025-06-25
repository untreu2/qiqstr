import 'dart:async';
import 'dart:collection';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/services/media_service.dart';

class NotePreloadItem {
  final NoteModel note;
  final DateTime addedAt;
  bool isProfileLoaded = false;
  bool isContentParsed = false;
  bool isMediaPreloaded = false;
  bool isReady = false;

  NotePreloadItem(this.note) : addedAt = DateTime.now();

  bool get isFullyLoaded => isProfileLoaded && isContentParsed && isMediaPreloaded;
}

class NotePreloaderService {
  final DataService _dataService;
  final Queue<NotePreloadItem> _preloadQueue = Queue();
  final Map<String, NotePreloadItem> _preloadItems = {};
  
  bool _isProcessing = false;
  Timer? _processingTimer;
  
  static const int maxConcurrentPreloads = 5;
  static const Duration preloadTimeout = Duration(seconds: 8);
  static const Duration processingInterval = Duration(milliseconds: 200);

  NotePreloaderService(this._dataService);

  void preloadNotes(List<NoteModel> notes) {
    for (final note in notes) {
      if (!_preloadItems.containsKey(note.id)) {
        final item = NotePreloadItem(note);
        _preloadItems[note.id] = item;
        _preloadQueue.add(item);
      }
    }
    
    _startProcessing();
  }

  bool isNoteReady(String noteId) {
    final item = _preloadItems[noteId];
    return item?.isReady ?? false;
  }

  double getNoteProgress(String noteId) {
    final item = _preloadItems[noteId];
    if (item == null) return 0.0;
    
    int completed = 0;
    if (item.isProfileLoaded) completed++;
    if (item.isContentParsed) completed++;
    if (item.isMediaPreloaded) completed++;
    
    return completed / 3.0;
  }

  String getNoteLoadingState(String noteId) {
    final item = _preloadItems[noteId];
    if (item == null) return 'Queued';
    if (item.isReady) return 'Ready';
    
    if (!item.isProfileLoaded) return 'Loading profile...';
    if (!item.isContentParsed) return 'Parsing content...';
    if (!item.isMediaPreloaded) return 'Loading media...';
    
    return 'Finalizing...';
  }

  void _startProcessing() {
    if (_isProcessing) return;
    
    _isProcessing = true;
    _processingTimer = Timer.periodic(processingInterval, (_) => _processQueue());
  }

  void _stopProcessing() {
    _isProcessing = false;
    _processingTimer?.cancel();
    _processingTimer = null;
  }

  Future<void> _processQueue() async {
    if (_preloadQueue.isEmpty) {
      _stopProcessing();
      return;
    }

    final itemsToProcess = <NotePreloadItem>[];
    for (int i = 0; i < maxConcurrentPreloads && _preloadQueue.isNotEmpty; i++) {
      itemsToProcess.add(_preloadQueue.removeFirst());
    }

    final futures = itemsToProcess.map((item) => _processNoteItem(item));
    await Future.wait(futures, eagerError: false);
  }

  Future<void> _processNoteItem(NotePreloadItem item) async {
    try {
      await _preloadNoteWithTimeout(item).timeout(
        preloadTimeout,
        onTimeout: () {
          item.isReady = true;
        },
      );
    } catch (e) {
      item.isReady = true;
    }
  }

  Future<void> _preloadNoteWithTimeout(NotePreloadItem item) async {
    if (!item.isProfileLoaded) {
      await _loadProfile(item);
    }

    if (!item.isContentParsed) {
      await _parseContent(item);
    }

    if (!item.isMediaPreloaded) {
      await _preloadMedia(item);
    }

    item.isReady = true;
  }

  Future<void> _loadProfile(NotePreloadItem item) async {
    try {
      if (_dataService.profilesNotifier.value.containsKey(item.note.author)) {
        item.isProfileLoaded = true;
        return;
      }

      await _dataService.fetchProfilesBatch([item.note.author]);
      
      final completer = Completer<void>();
      
      void profileListener() {
        if (_dataService.profilesNotifier.value.containsKey(item.note.author)) {
          _dataService.profilesNotifier.removeListener(profileListener);
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      }
      
      _dataService.profilesNotifier.addListener(profileListener);
      
      try {
        await completer.future.timeout(const Duration(seconds: 2));
        item.isProfileLoaded = true;
      } catch (e) {
        item.isProfileLoaded = true;
      }
      
      _dataService.profilesNotifier.removeListener(profileListener);
    } catch (e) {
      item.isProfileLoaded = true;
    }
  }

  Future<void> _parseContent(NotePreloadItem item) async {
    try {
      _dataService.parseContentForNote(item.note);
      item.isContentParsed = true;
    } catch (e) {
      item.isContentParsed = true;
    }
  }

  Future<void> _preloadMedia(NotePreloadItem item) async {
    try {
      if (!item.note.hasMedia) {
        item.isMediaPreloaded = true;
        return;
      }

      final parsed = item.note.parsedContent;
      if (parsed == null) {
        item.isMediaPreloaded = true;
        return;
      }

      final mediaUrls = List<String>.from(parsed['mediaUrls'] ?? []);
      if (mediaUrls.isEmpty) {
        item.isMediaPreloaded = true;
        return;
      }

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
        mediaService.cacheMediaUrls(imageUrls, priority: 2);
        
        await Future.delayed(const Duration(milliseconds: 500));
      }

      item.isMediaPreloaded = true;
    } catch (e) {
      item.isMediaPreloaded = true;
    }
  }

  void cleanup() {
    final cutoffTime = DateTime.now().subtract(const Duration(minutes: 10));
    
    _preloadItems.removeWhere((key, item) {
      return item.addedAt.isBefore(cutoffTime);
    });
  }

  Map<String, dynamic> getStats() {
    final total = _preloadItems.length;
    final ready = _preloadItems.values.where((item) => item.isReady).length;
    final queueSize = _preloadQueue.length;
    
    return {
      'total_items': total,
      'ready_items': ready,
      'queue_size': queueSize,
      'ready_percentage': total > 0 ? (ready / total * 100).round() : 0,
      'is_processing': _isProcessing,
    };
  }

  void dispose() {
    _stopProcessing();
    _preloadQueue.clear();
    _preloadItems.clear();
  }
}