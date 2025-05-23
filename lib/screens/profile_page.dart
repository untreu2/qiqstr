import 'package:flutter/material.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/widgets/profile_info_widget.dart';

class ProfilePage extends StatelessWidget {
  final UserModel user;

  const ProfilePage({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        cacheExtent: 1500,
        slivers: [
          SliverToBoxAdapter(
            child: ProfileInfoWidget(user: user),
          ),
          NoteListWidget(
            npub: user.npub,
            dataType: DataType.profile,
          ),
        ],
      ),
    );
  }
}
