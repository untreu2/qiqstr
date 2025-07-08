import 'package:flutter/material.dart';
import '../services/data_service.dart';
import '../colors.dart';

class SendReplyDialog extends StatefulWidget {
  final DataService dataService;
  final String noteId;

  const SendReplyDialog({
    Key? key,
    required this.dataService,
    required this.noteId,
  }) : super(key: key);

  @override
  _SendReplyDialogState createState() => _SendReplyDialogState();
}

class _SendReplyDialogState extends State<SendReplyDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _replyController = TextEditingController();
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

  Future<void> _sendReply() async {
    if (_isPosting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isPosting = true;
    });

    try {
      final replyContent = _replyController.text.trim();
      await widget.dataService.sendReply(widget.noteId, replyContent);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending reply: $error')),
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
                controller: _replyController,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Enter your reply',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a reply';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _connectionMessage,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _isPosting ? null : _sendReply,
                child: _isPosting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppColors.textPrimary),
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
    _replyController.dispose();
    super.dispose();
  }
}
