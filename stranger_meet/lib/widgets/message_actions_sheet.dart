import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MessageActionsSheet {
  static Future<String?> show(
    BuildContext context, {
    required bool isOwnMessage,
    required bool isTextMessage,
    required String messageText,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor:
          Theme.of(context).bottomSheetTheme.backgroundColor ??
          const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Edit (own text messages only)
              if (isOwnMessage && isTextMessage)
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: Colors.white70),
                  title: const Text(
                    'Edit message',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
              // Copy
              if (isTextMessage)
                ListTile(
                  leading: const Icon(Icons.copy_outlined, color: Colors.white70),
                  title: const Text(
                    'Copy text',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: messageText));
                    Navigator.pop(ctx, 'copy');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              // Delete for me
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.white70),
                title: const Text(
                  'Delete for me',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, 'delete_for_me'),
              ),
              // Delete for everyone (own messages only)
              if (isOwnMessage)
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever_outlined,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Delete for everyone',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () => Navigator.pop(ctx, 'delete_for_everyone'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
