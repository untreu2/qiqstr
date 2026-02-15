import '../../../core/bloc/base/base_state.dart';

abstract class InteractionState extends BaseState {
  const InteractionState();
}

class InteractionInitial extends InteractionState {
  const InteractionInitial();
}

class InteractionLoaded extends InteractionState {
  final int reactionCount;
  final int repostCount;
  final int replyCount;
  final int zapAmount;
  final bool hasReacted;
  final bool hasReposted;
  final bool hasZapped;
  final bool zapProcessing;
  final bool noteDeleted;

  const InteractionLoaded({
    this.reactionCount = 0,
    this.repostCount = 0,
    this.replyCount = 0,
    this.zapAmount = 0,
    this.hasReacted = false,
    this.hasReposted = false,
    this.hasZapped = false,
    this.zapProcessing = false,
    this.noteDeleted = false,
  });

  InteractionLoaded copyWith({
    int? reactionCount,
    int? repostCount,
    int? replyCount,
    int? zapAmount,
    bool? hasReacted,
    bool? hasReposted,
    bool? hasZapped,
    bool? zapProcessing,
    bool? noteDeleted,
  }) {
    return InteractionLoaded(
      reactionCount: reactionCount ?? this.reactionCount,
      repostCount: repostCount ?? this.repostCount,
      replyCount: replyCount ?? this.replyCount,
      zapAmount: zapAmount ?? this.zapAmount,
      hasReacted: hasReacted ?? this.hasReacted,
      hasReposted: hasReposted ?? this.hasReposted,
      hasZapped: hasZapped ?? this.hasZapped,
      zapProcessing: zapProcessing ?? this.zapProcessing,
      noteDeleted: noteDeleted ?? this.noteDeleted,
    );
  }

  @override
  List<Object?> get props => [
        reactionCount,
        repostCount,
        replyCount,
        zapAmount,
        hasReacted,
        hasReposted,
        hasZapped,
        zapProcessing,
        noteDeleted,
      ];
}
