import 'dart:async';
import 'package:flutter/foundation.dart';
import '../providers/user_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/interactions_provider.dart';
import 'base/service_base.dart';

// For the compute function to work, these functions must be
// outside a class or static.
// This structure makes it easy to send data to an isolate and process it there.

/// Standalone function to process secondary data in the background (Isolate).
Future<void> _processSecondaryDataInBackground(Map<String, dynamic> args) async {
  final List<String> noteIds = args['noteIds'];
  final String currentUserNpub = args['currentUserNpub'];

  // We may need to re-initialize providers within this isolate.
  // Or we can access the database directly here.
  // In this example, we assume that the providers are isolate-safe.
  await NotesProvider.instance.initialize(currentUserNpub);
  await InteractionsProvider.instance.initialize(currentUserNpub);

  const batchSize = 20;
  final interactionsProvider = InteractionsProvider.instance;

  for (int i = 0; i < noteIds.length; i += batchSize) {
    final batch = noteIds.skip(i).take(batchSize);
    for (final noteId in batch) {
      interactionsProvider.getReactionsForNote(noteId);
      interactionsProvider.getRepliesForNote(noteId);
      interactionsProvider.getRepostsForNote(noteId);
      interactionsProvider.getZapsForNote(noteId);
    }
    // No need for Future.delayed anymore as it runs inside an Isolate.
  }
}

/// Standalone function to process user profiles in the background (Isolate).
Future<void> _preloadProfilesInBackground(Map<String, dynamic> args) async {
  final List<String> authorIds = args['authorIds'];

  await UserProvider.instance.initialize();
  final userProvider = UserProvider.instance;
  const batchSize = 15;

  for (int i = 0; i < authorIds.length; i += batchSize) {
    final batch = authorIds.skip(i).take(batchSize).toList();
    await userProvider.loadUsers(batch);
  }
}

/// Optimized initialization service for faster app startup
class InitializationService extends LifecycleService with PerformanceMonitoringMixin {
  static InitializationService? _instance;
  static InitializationService get instance => _instance ??= InitializationService._internal();

  InitializationService._internal();

  bool _isInitialized = false;
  String? _currentUserNpub;

  @override
  bool get isInitialized => _isInitialized;

  /// Initialize app with ultra-fast startup strategy
  Future<void> initializeApp(String userNpub) async {
    if (_isInitialized) return;

    _currentUserNpub = userNpub;

    await measureOperation('app_initialization', () async {
      // Phase 1: Minimal critical initialization (ultra-fast)
      await _initializeMinimalCritical();

      // Phase 2: Progressive initialization (background)
      _scheduleProgressiveInitialization();

      _isInitialized = true;
    });
  }

  /// Initialize only the absolute minimum needed for UI display
  Future<void> _initializeMinimalCritical() async {
    await measureOperation('minimal_critical_init', () async {
      await UserProvider.instance.initialize();
    });
  }

  /// Schedule progressive initialization in background
  void _scheduleProgressiveInitialization() {
    // OPTIMIZATION: We are moving all heavy operations to Isolates instead of Future.microtask.
    // This ensures that the UI thread remains completely free.
    Future.microtask(() async {
      try {
        // Initialize necessary providers on the main thread
        await _initializeRemainingProviders();

        // OPTIMIZATION: Get the note list once and reuse it.
        final allNotes = NotesProvider.instance.getFeedNotes();

        // Load the critical cache (this should still be fast)
        await _loadCriticalCacheData(allNotes);

        // Offload remaining heavy operations to Isolates
        _offloadHeavyTasks(allNotes);
      } catch (e) {
        debugPrint('[InitializationService] Progressive initialization error: $e');
      }
    });
  }

  /// Initialize remaining providers in background
  Future<void> _initializeRemainingProviders() async {
    await measureOperation('remaining_providers_init', () async {
      // OPTIMIZATION: Guard clause for null check
      final userNpub = _currentUserNpub;
      if (userNpub == null || userNpub.isEmpty) return;

      await Future.wait([
        NotesProvider.instance.initialize(userNpub),
        InteractionsProvider.instance.initialize(userNpub),
      ]);
    });
  }

  /// Load critical cache data for immediate display
  Future<void> _loadCriticalCacheData(List<dynamic> allNotes) async {
    await measureOperation('critical_cache_load', () async {
      final interactionsProvider = InteractionsProvider.instance;
      final criticalNotes = allNotes.take(15).toList();

      // OPTIMIZATION: A single combined operation might be more efficient than calling them separately.
      // If the provider doesn't have such a method, the current structure is also acceptable.
      final criticalInteractionsFutures = criticalNotes.map((note) {
        // Ideally, the provider should have a method like preloadInteractions(note.id).
        return interactionsProvider.preloadInteractionsForNote(note.id);
      }).toList();

      await Future.wait(criticalInteractionsFutures);
    });
  }

  /// Offload heavy data processing tasks to background isolates
  void _offloadHeavyTasks(List<dynamic> allNotes) {
    final userNpub = _currentUserNpub;
    if (userNpub == null || userNpub.isEmpty) return;

    // --- Task 1: Load secondary cache in the background ---
    final remainingNoteIds = allNotes.skip(15).map((note) => note.id as String).toList();
    if (remainingNoteIds.isNotEmpty) {
      compute(_processSecondaryDataInBackground, {
        'noteIds': remainingNoteIds,
        'currentUserNpub': userNpub,
      }).catchError((e) => debugPrint('Secondary cache processing failed: $e'));
    }

    // --- Task 2: Preload user profiles in the background ---
    final uniqueAuthors = allNotes.fold<Set<String>>(<String>{}, (prev, note) {
      prev.add(note.author);
      if (note.repostedBy != null) {
        prev.add(note.repostedBy!);
      }
      return prev;
    }).toList();

    if (uniqueAuthors.isNotEmpty) {
      compute(_preloadProfilesInBackground, {
        'authorIds': uniqueAuthors,
        'currentUserNpub': userNpub,
      }).catchError((e) => debugPrint('User profile preloading failed: $e'));
    }
  }

  // OPTIMIZATION: These two methods are now managed within _offloadHeavyTasks and
  // the standalone functions called with compute (_processSecondaryDataInBackground,
  // _preloadProfilesInBackground). Therefore, they can be removed.
  // Future<void> _loadSecondaryCacheData() async { ... }
  // Future<void> _preloadUserProfiles() async { ... }

  /// Get initialization performance stats
  Map<String, dynamic> getInitializationStats() {
    final stats = getPerformanceStats();
    stats['isInitialized'] = _isInitialized;
    stats['currentUserNpub'] = _currentUserNpub;
    return stats;
  }

  /// Reset initialization state (for testing or re-initialization)
  Future<void> reset() async {
    _isInitialized = false;
    _currentUserNpub = null;
    clearPerformanceStats();
  }

  @override
  Future<void> onInitialize() async {}

  @override
  Future<void> onClose() async {
    await reset();
  }
}

// Having a combined method like this in InteractionsProvider improves performance.
extension InteractionsProviderExtension on InteractionsProvider {
  Future<void> preloadInteractionsForNote(String noteId) {
    return Future.wait([
      getReactionsForNote(noteId),
      getRepliesForNote(noteId),
      getRepostsForNote(noteId),
      getZapsForNote(noteId),
    ] as Iterable<Future>);
  }
}
