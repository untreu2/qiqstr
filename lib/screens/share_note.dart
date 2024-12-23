import 'package:flutter/material.dart';
import '../services/qiqstr_service.dart';

class ShareNoteDialog extends StatefulWidget {
  final DataService dataService;

  const ShareNoteDialog({Key? key, required this.dataService}) : super(key: key);

  @override
  _ShareNoteDialogState createState() => _ShareNoteDialogState();
}

class _ShareNoteDialogState extends State<ShareNoteDialog> {
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _noteFocusNode = FocusNode();
  String _connectionMessage = 'Connecting to relays...';
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
            _connectionMessage = 'CONNECTED TO ${widget.dataService.connectedRelaysCount} RELAYS.';
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
  return FractionallySizedBox(
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
          const Spacer(),
          SizedBox(
            width: double.infinity, 
            child: ElevatedButton(
              onPressed: _isPosting ? null : _shareNote,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24.0),
                ),
                elevation: 2.0,
              ),
              child: _isPosting
                  ? const CircularProgressIndicator(
                      color: Colors.black,
                    )
                  : const Text(
                      'POST',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16.0,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

  @override
  void dispose() {
    _noteFocusNode.dispose();
    super.dispose();
  }
}
