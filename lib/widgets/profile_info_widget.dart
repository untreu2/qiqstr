import 'package:flutter/material.dart';
import 'package:qiqstr/models/user_model.dart';

class ProfileInfoWidget extends StatelessWidget {
  final UserModel user;

  const ProfileInfoWidget({Key? key, required this.user}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        user.banner.isNotEmpty
            ? Image.network(
                user.banner,
                width: double.infinity,
                height: 200.0,
                fit: BoxFit.cover,
              )
            : Container(
                width: double.infinity,
                height: 200.0,
                color: Colors.black,
              ),
        Container(
          width: double.infinity,
          color: Colors.black,
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 40.0,
                backgroundImage: user.profileImage.isNotEmpty
                    ? NetworkImage(user.profileImage)
                    : null,
                backgroundColor:
                    user.profileImage.isEmpty ? Colors.grey : null,
                child: user.profileImage.isEmpty
                    ? const Icon(
                        Icons.person,
                        size: 40.0,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 16.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name.isNotEmpty ? user.name : 'Anonymous',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20.0,
                      ),
                    ),
                    if (user.nip05.isNotEmpty)
                      Text(
                        user.nip05,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14.0,
                        ),
                      ),
                    if (user.lud16.isNotEmpty)
                      Text(
                        user.lud16,
                        style: TextStyle(
                          color: Colors.amber[800],
                          fontSize: 14.0,
                        ),
                      ),
                    if (user.about.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          user.about,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14.0,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16.0),
      ],
    );
  }
}
