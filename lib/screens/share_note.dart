import 'package:flutter/material.dart';
import '../services/qiqstr_service.dart';

class ShareNoteDialog extends StatefulWidget {
  final DataService dataService;

  const ShareNoteDialog({super.key, required this.dataService});

  @override
  _ShareNoteDialogState createState() => _ShareNoteDialogState();
}

class _ShareNoteDialogState extends State<ShareNoteDialog> {
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _noteFocusNode = FocusNode();
  String _connectionMessage = '';
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    widget.dataService.initializeConnections().then((_) {
      if (mounted) {
        setState(() {
          if (widget.dataService.connectedRelaysCount == 0) {
            _connectionMessage = 'No relay connections established.';
          } else {
            _connectionMessage =
                'CONNECTED TO ${widget.dataService.connectedRelaysCount} RELAYS.';
          }
        });
      }
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _connectionMessage = 'Error connecting to relays: $e';
        });
      }
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

      Navigator.pop(context);
    } catch (e) {
      debugPrint('Error sharing note: $e');
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
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          FractionallySizedBox(
            heightFactor: 0.75,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
          ),
          Positioned(
            right: 16,
            top: 16,
            child: _isPosting
                ? const CircularProgressIndicator(color: Colors.black)
                : IconButton(
                    icon: const Icon(Icons.arrow_upward, color: Colors.white),
                    onPressed: _shareNote,
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _noteFocusNode.dispose();
    super.dispose();
  }
}
