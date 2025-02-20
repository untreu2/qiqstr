import 'package:flutter/material.dart';
import '../services/qiqstr_service.dart';

class SendReplyDialog extends StatefulWidget {
  final DataService dataService;
  final String noteId;

  const SendReplyDialog(
      {Key? key, required this.dataService, required this.noteId})
      : super(key: key);

  @override
  _SendReplyDialogState createState() => _SendReplyDialogState();
}

class _SendReplyDialogState extends State<SendReplyDialog> {
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
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
      _replyFocusNode.requestFocus();
    });
  }

  Future<void> _sendReply() async {
    if (_isPosting) return;
    setState(() {
      _isPosting = true;
    });

    try {
      final replyContent = _replyController.text.trim();
      if (replyContent.isEmpty) {
        throw Exception('Reply content cannot be empty.');
      }

      await widget.dataService.sendReply(widget.noteId, replyContent);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reply sent successfully!')),
      );

      Navigator.pop(context);
    } catch (e) {
      print('Error sending reply: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending reply: $e')),
      );
    } finally {
      setState(() {
        _isPosting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FractionallySizedBox(
          heightFactor: 0.75,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _replyController,
                  focusNode: _replyFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'ENTER YOUR REPLY...',
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
                  onPressed: _sendReply,
                  color: Colors.white,
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _replyFocusNode.dispose();
    _replyController.dispose();
    super.dispose();
  }
}
