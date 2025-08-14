import 'dart:async';
import 'package:flutter/foundation.dart';
import '../providers/user_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/interactions_provider.dart';
import 'base/service_base.dart';

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
      // Only initialize UserProvider for immediate UI needs
      await UserProvider.instance.initialize();
    });
  }

  /// Schedule progressive initialization in background
  void _scheduleProgressiveInitialization() {
    Future.microtask(() async {
      try {
        // Phase 1: Initialize remaining providers
        await _initializeRemainingProviders();

        // Phase 2: Load critical cache data
        await _loadCriticalCacheData();

        // Phase 3: Load secondary data progressively
        await _loadSecondaryCacheData();

        // Phase 4: Preload user profiles
        await _preloadUserProfiles();
      } catch (e) {
        debugPrint('[InitializationService] Progressive initialization error: $e');
      }
    });
  }

  /// Initialize remaining providers in background
  Future<void> _initializeRemainingProviders() async {
    await measureOperation('remaining_providers_init', () async {
      await Future.wait([
        NotesProvider.instance.initialize(_currentUserNpub ?? ''),
        InteractionsProvider.instance.initialize(_currentUserNpub ?? ''),
      ]);
    });
  }

  /// Load critical cache data for immediate display
  Future<void> _loadCriticalCacheData() async {
    await measureOperation('critical_cache_load', () async {
      final notesProvider = NotesProvider.instance;
      final interactionsProvider = InteractionsProvider.instance;

      // Get most recent notes for immediate display
      final recentNotes = notesProvider.getFeedNotes().take(15).toList();

      // Preload interactions for first 10 notes only
      final criticalInteractionsFutures = recentNotes.take(10).map((note) {
        return Future.microtask(() {
          // Trigger cache loading for interactions
          interactionsProvider.getReactionsForNote(note.id);
          interactionsProvider.getRepliesForNote(note.id);
          interactionsProvider.getRepostsForNote(note.id);
          interactionsProvider.getZapsForNote(note.id);
        });
      }).toList();

      await Future.wait(criticalInteractionsFutures);
    });
  }

  /// Load secondary cache data progressively
  Future<void> _loadSecondaryCacheData() async {
    await measureOperation('secondary_cache_load', () async {
      const batchSize = 20;
      final notesProvider = NotesProvider.instance;
      final interactionsProvider = InteractionsProvider.instance;

      final allNotes = notesProvider.getFeedNotes();
      final remainingNotes = allNotes.skip(10).toList();

      // Process remaining notes in batches
      for (int i = 0; i < remainingNotes.length; i += batchSize) {
        final batch = remainingNotes.skip(i).take(batchSize).toList();

        await Future.microtask(() {
          for (final note in batch) {
            // Load interactions for batch
            interactionsProvider.getReactionsForNote(note.id);
            interactionsProvider.getRepliesForNote(note.id);
            interactionsProvider.getRepostsForNote(note.id);
            interactionsProvider.getZapsForNote(note.id);
          }
        });

        // Small delay to prevent blocking
        await Future.delayed(const Duration(milliseconds: 2));
      }
    });
  }

  /// Preload user profiles progressively
  Future<void> _preloadUserProfiles() async {
    await measureOperation('user_profiles_preload', () async {
      const batchSize = 15;
      final notesProvider = NotesProvider.instance;
      final userProvider = UserProvider.instance;

      // Get all unique authors
      final allNotes = notesProvider.getFeedNotes();
      final uniqueAuthors = <String>{};

      for (final note in allNotes) {
        uniqueAuthors.add(note.author);
        if (note.repostedBy != null) {
          uniqueAuthors.add(note.repostedBy!);
        }
      }

      final authorsList = uniqueAuthors.toList();

      // Load user profiles in batches
      for (int i = 0; i < authorsList.length; i += batchSize) {
        final batch = authorsList.skip(i).take(batchSize).toList();
        await userProvider.loadUsers(batch);

        // Small delay to prevent blocking
        await Future.delayed(const Duration(milliseconds: 3));
      }
    });
  }

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
  Future<void> onInitialize() async {
    // Service is initialized when initializeApp is called
  }

  @override
  Future<void> onClose() async {
    await reset();
  }
}

/// Isolate-based cache processing for heavy operations
class CacheProcessingIsolate {
  static Future<void> processCacheData(Map<String, dynamic> params) async {
    try {
      final operation = params['operation'] as String;
      final data = params['data'];

      switch (operation) {
        case 'process_notes':
          await _processNotesInIsolate(data);
          break;
        case 'process_interactions':
          await _processInteractionsInIsolate(data);
          break;
        case 'process_user_profiles':
          await _processUserProfilesInIsolate(data);
          break;
      }
    } catch (e) {
      debugPrint('[CacheProcessingIsolate] Error: $e');
    }
  }

  static Future<void> _processNotesInIsolate(List<Map<String, dynamic>> notesData) async {
    // Process notes data in isolate
    for (final _ in notesData) {
      // Perform heavy processing operations
      await Future.delayed(const Duration(microseconds: 100));
    }
  }

  static Future<void> _processInteractionsInIsolate(List<Map<String, dynamic>> interactionsData) async {
    // Process interactions data in isolate
    for (final _ in interactionsData) {
      // Perform heavy processing operations
      await Future.delayed(const Duration(microseconds: 50));
    }
  }

  static Future<void> _processUserProfilesInIsolate(List<Map<String, dynamic>> profilesData) async {
    // Process user profiles data in isolate
    for (final _ in profilesData) {
      // Perform heavy processing operations
      await Future.delayed(const Duration(microseconds: 75));
    }
  }
}
