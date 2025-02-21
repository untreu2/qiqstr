import 'package:flutter/material.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/widgets/profile_info_widget.dart';

class ProfilePage extends StatelessWidget {
  final UserModel user;

  const ProfilePage({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: SidebarWidget(user: user),
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: ProfileInfoWidget(user: user),
            ),
          ];
        },
        body: NoteListWidget(
          npub: user.npub,
          dataType: DataType.Profile,
        ),
      ),
    );
  }
}
