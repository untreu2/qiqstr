bool isImageUrl(String url) {
  return url.endsWith('.png') || url.endsWith('.jpg') || url.endsWith('.jpeg') || url.endsWith('.gif');
}

String formatDateTime(String timestamp) {
  final DateTime dateTime = DateTime.parse(timestamp);
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}
