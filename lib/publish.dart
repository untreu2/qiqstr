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

    Event signedEvent = _signEvent(nsec, content);

    List<Future<void>> futures = relayList.map((relay) => _broadcastEvent(signedEvent, relay)).toList();
    
    await Future.wait(futures);

    setState(() {
      _message = 'Note successfully shared!';
    });
  }

  Event _signEvent(String nsec, String content) {
    return Event.from(
      kind: 1,
      tags: [],
      content: content,
      privkey: nsec,
    );
  }

  Future<void> _broadcastEvent(Event signedEvent, String relay) async {
    try {
      WebSocket webSocket = await WebSocket.connect(relay);

      String signedEventJson = jsonEncode(["EVENT", signedEvent.toJson()]);

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
            Container(
              height: 150,
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  labelText: "Enter your note...",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _publishNote,
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.black, backgroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text('Share'),
              ),
            ),
            SizedBox(height: 20),
            Text(_message),
          ],
        ),
      ),
    );
  }
}
