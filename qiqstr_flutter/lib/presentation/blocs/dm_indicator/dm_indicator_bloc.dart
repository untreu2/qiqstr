import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/services/auth_service.dart';
import '../dm/dm_bloc.dart';
import '../dm/dm_state.dart';
import 'dm_indicator_event.dart';
import 'dm_indicator_state.dart';

class DmIndicatorBloc extends Bloc<DmIndicatorEvent, DmIndicatorState> {
  final DmBloc _dmBloc;
  final AuthService _authService;

  static const String _lastCheckedKey = 'dm_indicator_last_checked_timestamp';

  int _lastCheckedTimestamp = 0;
  StreamSubscription<DmState>? _dmStateSubscription;
  String? _currentUserHex;
  int _generation = 0;

  DmIndicatorBloc({
    required DmBloc dmBloc,
    required AuthService authService,
  })  : _dmBloc = dmBloc,
        _authService = authService,
        super(const DmIndicatorInitial()) {
    on<DmIndicatorInitialized>(_onInitialized, transformer: restartable());
    on<DmIndicatorChecked>(_onChecked);
    on<_DmConversationsDataUpdated>(_onConversationsDataUpdated);
  }

  Future<void> _onInitialized(
    DmIndicatorInitialized event,
    Emitter<DmIndicatorState> emit,
  ) async {
    final userHex = _authService.currentUserPubkeyHex;
    final generation = ++_generation;
    _currentUserHex = userHex;
    await _dmStateSubscription?.cancel();
    _dmStateSubscription = null;
    if (generation != _generation || emit.isDone) return;
    if (userHex == null || userHex.isEmpty) {
      _lastCheckedTimestamp = 0;
      emit(const DmIndicatorLoaded(hasNewMessages: false));
      return;
    }

    _lastCheckedTimestamp = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastCheckedTimestamp = prefs.getInt(_keyForUser(userHex)) ?? 0;
    } catch (_) {}
    if (generation != _generation ||
        _currentUserHex != userHex ||
        emit.isDone) {
      return;
    }

    emit(const DmIndicatorLoaded(hasNewMessages: false));

    _dmStateSubscription = _dmBloc.stream.listen((dmState) {
      if (isClosed || generation != _generation || _currentUserHex != userHex) {
        return;
      }
      if (dmState is DmConversationsLoaded) {
        if (_dmBloc.conversationsUserHex != userHex) return;
        add(_DmConversationsDataUpdated(
          dmState.conversations,
          userHex,
          generation,
        ));
      }
    });

    final currentDmState = _dmBloc.state;
    if (currentDmState is DmConversationsLoaded &&
        _dmBloc.conversationsUserHex == userHex) {
      add(_DmConversationsDataUpdated(
        currentDmState.conversations,
        userHex,
        generation,
      ));
    }
  }

  String _keyForUser(String userHex) => '${_lastCheckedKey}_$userHex';

  void _onConversationsDataUpdated(
    _DmConversationsDataUpdated event,
    Emitter<DmIndicatorState> emit,
  ) {
    if (event.generation != _generation || event.userHex != _currentUserHex) {
      return;
    }
    if (_lastCheckedTimestamp == 0) {
      final latestTimestamp = _latestTimestamp(event.conversations);
      if (latestTimestamp > 0) {
        _lastCheckedTimestamp = latestTimestamp;
        _persistTimestamp(_lastCheckedTimestamp, event.userHex);
      }
      emit(const DmIndicatorLoaded(hasNewMessages: false));
      return;
    }

    final latestTimestamp = _latestTimestamp(event.conversations);
    final hasNew = latestTimestamp > _lastCheckedTimestamp;
    emit(DmIndicatorLoaded(hasNewMessages: hasNew));
  }

  int _latestTimestamp(List<Map<String, dynamic>> conversations) {
    if (conversations.isEmpty) return 0;
    int latest = 0;
    for (final conv in conversations) {
      final lastMessage = conv['lastMessage'] as Map<String, dynamic>?;
      if (lastMessage == null) continue;
      if (lastMessage['isFromCurrentUser'] == true) continue;

      final lastMessageTime = conv['lastMessageTime'];
      int ts = 0;
      if (lastMessageTime is DateTime) {
        ts = lastMessageTime.millisecondsSinceEpoch ~/ 1000;
      } else if (lastMessageTime is int) {
        ts = lastMessageTime;
      }
      if (ts > latest) latest = ts;
    }
    return latest;
  }

  Future<void> _onChecked(
    DmIndicatorChecked event,
    Emitter<DmIndicatorState> emit,
  ) async {
    final userHex = _currentUserHex;
    final generation = _generation;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _lastCheckedTimestamp = now;
    if (userHex != null) {
      await _persistTimestamp(_lastCheckedTimestamp, userHex);
    }
    if (!emit.isDone &&
        generation == _generation &&
        _currentUserHex == userHex) {
      emit(const DmIndicatorLoaded(hasNewMessages: false));
    }
  }

  Future<void> _persistTimestamp(int timestamp, String userHex) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyForUser(userHex), timestamp);
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _generation++;
    _dmStateSubscription?.cancel();
    return super.close();
  }
}

class _DmConversationsDataUpdated extends DmIndicatorEvent {
  final List<Map<String, dynamic>> conversations;
  final String userHex;
  final int generation;

  const _DmConversationsDataUpdated(
    this.conversations,
    this.userHex,
    this.generation,
  );

  @override
  List<Object?> get props => [conversations, userHex, generation];
}
