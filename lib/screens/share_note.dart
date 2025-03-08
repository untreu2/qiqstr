import 'package:flutter/material.dart';
import '../services/qiqstr_service.dart';

class ShareNoteDialog extends StatefulWidget {
  final DataService dataService;

  const ShareNoteDialog({Key? key, required this.dataService})
      : super(key: key);

  @override
  _ShareNoteDialogState createState() => _ShareNoteDialogState();
}

class _ShareNoteDialogState extends State<ShareNoteDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _noteController = TextEditingController();
  bool _isPosting = false;
  String _connectionMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeConnection();
  }

  Future<void> _initializeConnection() async {
    try {
      await widget.dataService.initializeConnections();
      setState(() {
        _connectionMessage = widget.dataService.connectedRelaysCount > 0
            ? 'Connected to ${widget.dataService.connectedRelaysCount} relays'
            : 'No relay connections established';
      });
    } catch (error) {
      setState(() {
        _connectionMessage = 'Error connecting: $error';
      });
    }
  }

  Future<void> _shareNote() async {
    if (_isPosting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isPosting = true;
    });

    try {
      final noteContent = _noteController.text.trim();
      await widget.dataService.shareNote(noteContent);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing note: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPosting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _noteController,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Enter your note',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a note';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _connectionMessage,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _isPosting ? null : _shareNote,
                child: _isPosting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.black),
                        ),
                      )
                    : const Text('Share'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }
}
