import 'package:flutter/material.dart';
import '../services/qiqstr_service.dart';

class ShareNotePage extends StatefulWidget {
  final DataService dataService;

  const ShareNotePage({Key? key, required this.dataService}) : super(key: key);

  @override
  _ShareNotePageState createState() => _ShareNotePageState();
}

class _ShareNotePageState extends State<ShareNotePage> {
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _noteFocusNode = FocusNode();
  String _connectionMessage = 'Connecting to relays...';
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();

    widget.dataService.initializeConnections().then((_) {
      setState(() {
        if (widget.dataService.connectedRelaysCount == 0) {
          _connectionMessage = 'No relay connections established.';
        } else {
          _connectionMessage = 'CONNECTED TO ${widget.dataService.connectedRelaysCount} RELAYS.';
        }
      });
    }).catchError((e) {
      setState(() {
        _connectionMessage = 'Error connecting to relays: $e';
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _noteFocusNode.requestFocus();
    });
  }

  Future<void> _shareNote() async {
    if (_isPosting) return;
    setState(() {
      _isPosting = true;
    });

    try {
      final noteContent = _noteController.text.trim();
      if (noteContent.isEmpty) {
        throw Exception('Note content cannot be empty.');
      }

      await widget.dataService.shareNote(noteContent);

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
    _noteFocusNode.dispose();
    super.dispose();
  }
}
