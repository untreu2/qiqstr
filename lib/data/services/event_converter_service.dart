import '../../models/event_model.dart';

class EventConverterService {
  static EventConverterService? _instance;
  static EventConverterService get instance => _instance ??= EventConverterService._internal();

  EventConverterService._internal();

  EventModel eventDataToModel(Map<String, dynamic> eventData, {String? relayUrl}) {
    return EventModel.fromEventData(eventData, relayUrl: relayUrl);
  }

  Map<String, dynamic> modelToEventData(EventModel eventModel) {
    return eventModel.toEventData();
  }

  List<EventModel> eventDataListToModels(
    List<Map<String, dynamic>> eventDataList, {
    String? relayUrl,
  }) {
    return eventDataList
        .map((eventData) => eventDataToModel(eventData, relayUrl: relayUrl))
        .toList();
  }

  List<Map<String, dynamic>> modelsToEventDataList(List<EventModel> eventModels) {
    return eventModels.map((model) => modelToEventData(model)).toList();
  }

  List<Map<String, dynamic>>? modelsToEventDataListOrNull(List<EventModel>? eventModels) {
    if (eventModels == null) return null;
    return modelsToEventDataList(eventModels);
  }
}
