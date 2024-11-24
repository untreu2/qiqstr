import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  Future<void> _saveNsecAndNpub(String nsecBech32) async {
    try {
      final nsecHex = Nip19.decodePrivkey(nsecBech32);

      if (nsecHex.isEmpty) {
        throw Exception('Invalid nsec format.');
      }

      final keychain = Keychain(nsecHex);
      final npubHex = keychain.public;

      await _secureStorage.write(key: 'privateKey', value: nsecHex);
      await _secureStorage.write(key: 'npub', value: npubHex);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FeedPage(npub: npubHex),
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
        title: const Text('Welcome to Qiqstr!'),
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  _saveNsecAndNpub(_nsecController.text);
                },
                child: const Text('Login'),
              ),
            ),
            const SizedBox(height: 20),
            Text(_message),
          ],
        ),
      ),
    );
  }
}
