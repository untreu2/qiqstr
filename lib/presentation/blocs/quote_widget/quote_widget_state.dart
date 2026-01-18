import '../../../core/bloc/base/base_state.dart';

abstract class QuoteWidgetState extends BaseState {
  const QuoteWidgetState();
}

class QuoteWidgetInitial extends QuoteWidgetState {
  const QuoteWidgetInitial();
}

class QuoteWidgetLoading extends QuoteWidgetState {
  const QuoteWidgetLoading();
}

class QuoteWidgetLoaded extends QuoteWidgetState {
  final Map<String, dynamic> note;
  final Map<String, dynamic>? user;
  final String? formattedTime;
  final Map<String, dynamic>? parsedContent;
  final bool shouldTruncate;

  const QuoteWidgetLoaded({
    required this.note,
    this.user,
    this.formattedTime,
    this.parsedContent,
    this.shouldTruncate = false,
  });

  @override
  List<Object?> get props => [note, user, formattedTime, parsedContent, shouldTruncate];
}

class QuoteWidgetError extends QuoteWidgetState {
  const QuoteWidgetError();
}
