import 'dart:async';

class StreamDebouncer<T> {
  final Duration duration;
  final StreamController<T> _inputController = StreamController<T>();
  final StreamController<T> _outputController = StreamController<T>.broadcast();
  StreamSubscription<T>? _subscription;

  StreamDebouncer({required this.duration}) {
    _subscription = _inputController.stream
        .transform(
          StreamTransformer<T, T>.fromHandlers(
            handleData: (data, sink) {
              sink.add(data);
            },
          ),
        )
        .debounceTime(duration)
        .listen(_outputController.add);
  }

  void add(T value) {
    if (!_inputController.isClosed) {
      _inputController.add(value);
    }
  }

  Stream<T> get stream => _outputController.stream;

  void dispose() {
    _subscription?.cancel();
    _inputController.close();
    _outputController.close();
  }
}

extension StreamDebounce<T> on Stream<T> {
  Stream<T> debounceTime(Duration duration) {
    StreamSubscription<T>? subscription;
    StreamController<T>? controller;
    DateTime? lastEventTime;

    controller = StreamController<T>(
      onListen: () {
        subscription = listen(
          (data) {
            lastEventTime = DateTime.now();
            final capturedTime = lastEventTime!;

            Future.delayed(duration, () {
              if (lastEventTime == capturedTime && 
                  controller != null && 
                  !controller.isClosed) {
                controller.add(data);
              }
            });
          },
          onError: (error) {
            if (controller != null && !controller.isClosed) {
              controller.addError(error);
            }
          },
          onDone: () {
            if (controller != null && !controller.isClosed) {
              controller.close();
            }
          },
        );
      },
      onCancel: () => subscription?.cancel(),
    );

    return controller.stream;
  }
}

class ValueDebouncer<T> {
  final Duration duration;
  T? _pendingValue;
  DateTime? _lastAddTime;
  final void Function(T) onValue;

  ValueDebouncer({required this.duration, required this.onValue});

  void add(T value) {
    _pendingValue = value;
    final addTime = DateTime.now();
    _lastAddTime = addTime;

    Future.delayed(duration, () {
      if (_lastAddTime == addTime && _pendingValue != null) {
        onValue(_pendingValue as T);
        _pendingValue = null;
      }
    });
  }

  void dispose() {
    _pendingValue = null;
    _lastAddTime = null;
  }
}

