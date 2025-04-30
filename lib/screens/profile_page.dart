import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qiqstr/widgets/note_list_widget.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/widgets/profile_info_widget.dart';

class ProfilePage extends StatefulWidget {
  final UserModel user;

  const ProfilePage({super.key, required this.user});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _showOverlay = false;

  @override
  void initState() {
    super.initState();
    _checkAndMaybeRestart();
  }

  Future<void> _checkAndMaybeRestart() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'profile_refresh_done_${widget.user.npub}';
    final alreadyDone = prefs.getBool(key) ?? false;

    if (!alreadyDone) {
      setState(() => _showOverlay = true);

      await Future.delayed(const Duration(seconds: 2));
      await prefs.setBool(key, true);

      if (!mounted) return;

      Navigator.of(context).pop();

      await Future.delayed(const Duration(milliseconds: 150));

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ProfilePage(user: widget.user),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            cacheExtent: 1500,
            slivers: [
              SliverToBoxAdapter(
                child: ProfileInfoWidget(user: widget.user),
              ),
              NoteListWidget(
                npub: widget.user.npub,
                dataType: DataType.Profile,
              ),
            ],
          ),
          if (_showOverlay)
            Container(
              color: Colors.black.withOpacity(0.95),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      "Loading for first time...",
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
