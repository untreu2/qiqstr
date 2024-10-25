import 'package:flutter/material.dart';

class NoteWidget extends StatelessWidget {
  final Map<String, dynamic> note;

  const NoteWidget({Key? key, required this.note}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: NetworkImage(note['profileImage']),
      ),
      title: Text(note['name']),
      subtitle: Text(note['content']),
      trailing: Text(note['timestamp']),
      onTap: () {
      },
    );
  }
}
