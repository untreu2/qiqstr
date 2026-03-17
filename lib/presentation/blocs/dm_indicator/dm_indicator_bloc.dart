import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../dm/dm_bloc.dart';
import '../dm/dm_state.dart';
import 'dm_indicator_event.dart';
import 'dm_indicator_state.dart';

class DmIndicatorBloc extends Bloc<DmIndicatorEvent, DmIndicatorState> {
  final DmBloc _dmBloc;

  static const String _lastCheckedKey = 'dm_indicator_last_checked_timestamp';

  int _lastCheckedTimestamp = 0;
  StreamSubscription<DmState>? _dmStateSubscription;

  DmIndicatorBloc({required DmBloc dmBloc})
      : _dmBloc = dmBloc,
        super(const DmIndicatorInitial()) {
    on<DmIndicatorInitialized>(_onInitialized);
    on<DmIndicatorChecked>(_onChecked);
    on<_DmConversationsDataUpdated>(_onConversationsDataUpdated);
  }

  Future<void> _onInitialized(
    DmIndicatorInitialized event,
    Emitter<DmIndicatorState> emit,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastCheckedTimestamp = prefs.getInt(_lastCheckedKey) ?? 0;
    } catch (_) {}

    emit(const DmIndicatorLoaded(hasNewMessages: false));

    _dmStateSubscription?.cancel();
    _dmStateSubscription = _dmBloc.stream.listen((dmState) {
      if (isClosed) return;
      if (dmState is DmConversationsLoaded) {
        add(_DmConversationsDataUpdated(dmState.conversations));
      }
    });

    final currentDmState = _dmBloc.state;
    if (currentDmState is DmConversationsLoaded) {
      add(_DmConversationsDataUpdated(currentDmState.conversations));
    }
  }

  void _onConversationsDataUpdated(
    _DmConversationsDataUpdated event,
    Emitter<DmIndicatorState> emit,
  ) {
    if (_lastCheckedTimestamp == 0) {
      final latestTimestamp = _latestTimestamp(event.conversations);
      if (latestTimestamp > 0) {
        _lastCheckedTimestamp = latestTimestamp;
        _persistTimestamp(_lastCheckedTimestamp);
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
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _lastCheckedTimestamp = now;
    await _persistTimestamp(_lastCheckedTimestamp);
    emit(const DmIndicatorLoaded(hasNewMessages: false));
  }

  Future<void> _persistTimestamp(int timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckedKey, timestamp);
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _dmStateSubscription?.cancel();
    return super.close();
  }
}

class _DmConversationsDataUpdated extends DmIndicatorEvent {
  final List<Map<String, dynamic>> conversations;
  const _DmConversationsDataUpdated(this.conversations);

  @override
  List<Object?> get props => [conversations];
}
