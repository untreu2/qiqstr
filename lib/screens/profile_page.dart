import 'package:flutter/material.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/services/qiqstr_service.dart';

class ProfilePage extends StatelessWidget {
  final String npub;

  const ProfilePage({Key? key, required this.npub}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NoteListWidget(
        npub: npub,
        dataType: DataType.Profile,
      ),
    );
  }
}