import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nostr/nostr.dart';
import 'feed_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nsecController = TextEditingController();
  String _message = '';

  Future<void> _saveNsecAndNpub(String nsecBech32) async {
    try {
      final nsecHex = Nip19.decodePrivkey(nsecBech32);

      if (nsecHex.isEmpty) {
        throw Exception('Invalid nsec format.');
      }

      final keychain = Keychain(nsecHex);
      final npub = keychain.public;

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('privateKey', nsecHex);
      await prefs.setString('npub', npub);

      setState(() {
        _message = 'NSEC and NPUB saved!';
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FeedPage(npub: npub),
        ),
      );
    } catch (e) {
      setState(() {
        _message = 'Error: Invalid nsec input.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextField(
              controller: _nsecController,
              decoration: const InputDecoration(
                labelText: 'Enter your nsec...',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                _saveNsecAndNpub(_nsecController.text);
              },
              child: const Text('Login'),
            ),
            const SizedBox(height: 20),
            Text(_message),
          ],
        ),
      ),
    );
  }
}
