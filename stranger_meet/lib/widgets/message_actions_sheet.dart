import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MessageActionsSheet {
  static const _quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  static Future<String?> show(
    BuildContext context, {
    required bool isOwnMessage,
    required bool isTextMessage,
    required String messageText,
    bool showPin = false,
    bool isPinned = false,
    bool isAdmin = false,
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
                margin: const EdgeInsets.only(top: 12, bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Quick emoji reaction row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ..._quickEmojis.map((emoji) => _EmojiButton(
                      emoji: emoji,
                      onTap: () => Navigator.pop(ctx, 'react:$emoji'),
                    )),
                    // "+" button for more emojis
                    _EmojiButton(
                      emoji: '+',
                      isPlus: true,
                      onTap: () => Navigator.pop(ctx, 'react:more'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              // Reply
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.white70),
                title: const Text(
                  'Reply',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, 'reply'),
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
              // Pin/Unpin (admin only, group chats)
              if (showPin && isAdmin)
                ListTile(
                  leading: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: Colors.white70,
                  ),
                  title: Text(
                    isPinned ? 'Unpin message' : 'Pin message',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(ctx, isPinned ? 'unpin' : 'pin'),
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
              if (isOwnMessage || isAdmin)
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

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final bool isPlus;
  final VoidCallback onTap;

  const _EmojiButton({
    required this.emoji,
    required this.onTap,
    this.isPlus = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(21),
        ),
        alignment: Alignment.center,
        child: isPlus
            ? const Icon(Icons.add, color: Colors.white70, size: 20)
            : Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

/// Displays emoji reactions below a message bubble.
class MessageReactionsRow extends StatelessWidget {
  final List<Map<String, dynamic>> reactions;
  final String? currentUserId;
  final bool isMe;
  final void Function(String emoji)? onTapReaction;

  const MessageReactionsRow({
    super.key,
    required this.reactions,
    this.currentUserId,
    this.isMe = false,
    this.onTapReaction,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Wrap(
          spacing: 4,
          children: reactions.map((r) {
            final emoji = r['emoji'] as String;
            final count = r['count'] as int;
            final userIds = (r['user_ids'] as List?)?.cast<String>() ?? [];
            final iReacted = currentUserId != null && userIds.contains(currentUserId);

            return GestureDetector(
              onTap: () => onTapReaction?.call(emoji),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: iReacted
                      ? Colors.blue.withOpacity(0.25)
                      : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: iReacted
                      ? Border.all(color: Colors.blue.withOpacity(0.5), width: 1)
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 14)),
                    if (count > 1) ...[
                      const SizedBox(width: 2),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[400],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
