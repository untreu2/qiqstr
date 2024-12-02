import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart';
import '../services/qiqstr_service.dart';

class ShareNotePage extends StatefulWidget {
  final DataService dataService;

  const ShareNotePage({Key? key, required this.dataService}) : super(key: key);

  @override
  _ShareNotePageState createState() => _ShareNotePageState();
}

class _ShareNotePageState extends State<ShareNotePage> {
  final TextEditingController _noteController = TextEditingController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final FocusNode _noteFocusNode = FocusNode();
  late Map<String, WebSocket> _relayConnections;
  String _connectionMessage = 'Connecting to relays...';
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _relayConnections = {};

    _connectToRelays();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _noteFocusNode.requestFocus();
    });
  }

  Future<void> _connectToRelays() async {
    try {
      final relayUrls = widget.dataService.relayUrls;

      for (var url in relayUrls) {
        try {
          final webSocket = await WebSocket.connect(url);
          _relayConnections[url] = webSocket;
          print('Connected to relay: $url');
        } catch (e) {
          print('Failed to connect to relay: $url, Error: $e');
        }
      }

      setState(() {
        if (_relayConnections.isEmpty) {
          _connectionMessage = 'No relay connections established.';
        } else {
          _connectionMessage = 'CONNECTED TO ${_relayConnections.length} RELAYS.';
        }
      });
    } catch (e) {
      setState(() {
        _connectionMessage = 'Error connecting to relays: $e';
      });
    }
  }

  Future<void> _shareNote() async {
    if (_isPosting) return;
    setState(() {
      _isPosting = true;
    });

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found. Please log in again.');
      }

      final noteContent = _noteController.text.trim();
      if (noteContent.isEmpty) {
        throw Exception('Note content cannot be empty.');
      }

      if (_relayConnections.isEmpty) {
        throw Exception('No active relay connections. Note cannot be shared.');
      }

      final event = Event.from(
        kind: 1,
        tags: [],
        content: noteContent,
        privkey: privateKey,
      );

      for (var relayUrl in _relayConnections.keys) {
        try {
          _relayConnections[relayUrl]?.add(event.serialize());
          print('Note shared with relay: $relayUrl');
        } catch (e) {
          print('Error sending note to relay $relayUrl: $e');
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note shared successfully!')),
      );

      Navigator.pop(context);
    } catch (e) {
      print('Error sharing note: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing note: $e')),
      );
    } finally {
      setState(() {
        _isPosting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _noteController,
                focusNode: _noteFocusNode,
                decoration: const InputDecoration(
                  labelText: 'ENTER YOUR NOTE...',
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 20),
              Text(
                _connectionMessage,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SizedBox(
            width: double.infinity,
            height: 48.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20.0,
                    spreadRadius: 2.0,
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                onPressed: _shareNote,
                label: _isPosting
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                      )
                    : const Text(
                        'POST',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  @override
  void dispose() {
    for (var connection in _relayConnections.values) {
      connection.close();
    }
    _noteFocusNode.dispose();
    super.dispose();
  }
}
