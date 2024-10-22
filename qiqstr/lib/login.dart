 import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nostr_tools/nostr_tools.dart' as nostr_tools;
import 'package:nostr/nostr.dart';
import 'feed.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nsecController = TextEditingController();
  String _message = '';

  Future<void> _saveNsecAndNpub(String nsec) async {
    try {
      final nip19 = nostr_tools.Nip19();
      final decodedNsec = nip19.decode(nsec);
      final nsecHex = decodedNsec['data'];

      final npubHex = deriveNpubFromNsecHex(nsecHex);

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('privateKey', nsecHex);
      await prefs.setString('npub', npubHex);

      setState(() {
        _message = 'NSEC and NPUB saved!';
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FeedPage(npub: npubHex),
        ),
      );
    } catch (e) {
      setState(() {
        _message = 'Error: Invalid NSEC input.';
      });
    }
  }

  String deriveNpubFromNsecHex(String nsecHex) {
    var keychain = Keychain(nsecHex);
    return keychain.public;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('NSEC Login'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextField(
              controller: _nsecController,
              decoration: InputDecoration(
                labelText: 'Enter NSEC (nsec1...)',
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                _saveNsecAndNpub(_nsecController.text);
              },
              child: Text('Login'),
            ),
            SizedBox(height: 20),
            Text(_message),
          ],
        ),
      ),
    );
  }
}
