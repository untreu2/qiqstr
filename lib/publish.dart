import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nostr/nostr.dart';

class PublishPage extends StatefulWidget {
  @override
  _PublishPageState createState() => _PublishPageState();
}

class _PublishPageState extends State<PublishPage> {
  final TextEditingController _contentController = TextEditingController();
  String _message = '';

  Future<void> _publishNote() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? nsec = prefs.getString('privateKey');
    List<String>? relayList = prefs.getStringList('relayList');

    if (nsec == null || relayList == null || relayList.isEmpty) {
      setState(() {
        _message = 'nsec or relay list not found.';
      });
      return;
    }

    String content = _contentController.text;

    for (String relay in relayList) {
      await _broadcastEvent(nsec, content, relay);
    }

    setState(() {
      _message = 'Note successfully shared!';
    });
  }

  Future<void> _broadcastEvent(String nsec, String content, String relay) async {
    try {
      WebSocket webSocket = await WebSocket.connect(relay);

      Event newEvent = Event.from(
        kind: 1,
        tags: [],
        content: content,
        privkey: nsec,
      );

      String signedEventJson = jsonEncode(["EVENT", newEvent.toJson()]);

      webSocket.add(signedEventJson);

      webSocket.listen((event) {
        print('Response from relay: $event');
      });

      await Future.delayed(Duration(seconds: 5));
      await webSocket.close();
    } catch (e) {
      print('Error connecting to relay: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Share note'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextField(
              controller: _contentController,
              decoration: InputDecoration(
                labelText: "Enter your note...",
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _publishNote,
              child: Text('Share'),
            ),
            SizedBox(height: 20),
            Text(_message),
          ],
        ),
      ),
    );
  }
}
