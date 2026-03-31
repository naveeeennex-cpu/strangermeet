import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../config/theme.dart';
import '../../services/api_service.dart';

class EventMemoriesScreen extends ConsumerStatefulWidget {
  final String eventId;
  final String eventTitle;
  final bool canUpload;

  const EventMemoriesScreen({
    super.key,
    required this.eventId,
    this.eventTitle = 'Memories',
    this.canUpload = false,
  });

  @override
  ConsumerState<EventMemoriesScreen> createState() =>
      _EventMemoriesScreenState();
}

class _EventMemoriesScreenState extends ConsumerState<EventMemoriesScreen> {
  List<Map<String, dynamic>> _memories = [];
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _fetchMemories();
  }

  Future<void> _fetchMemories() async {
    try {
      final response = await ApiService()
          .get('/bookings/events/${widget.eventId}/memories');
      final data = response.data;
      if (mounted) {
        setState(() {
          _memories =
              (data is List ? data : []).cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadMemory() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (picked == null) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: picked.name),
        'folder': 'memories',
      });
      final uploadResp =
          await ApiService().uploadFile('/upload', formData: formData);
      final url = uploadResp.data['url'];

      await ApiService()
          .post('/bookings/events/${widget.eventId}/memories', data: {
        'media_url': url,
        'media_type': 'image',
      });

      await _fetchMemories();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Memory uploaded!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showFullScreen(Map<String, dynamic> memory) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, _, __) =>
            _FullScreenMemory(memory: memory),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Memories',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(widget.eventTitle,
                style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color)),
          ],
        ),
        actions: [
          if (widget.canUpload)
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _isUploading ? null : _uploadMemory,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _memories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 64,
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.4)),
                      const SizedBox(height: 16),
                      Text('No memories yet',
                          style: TextStyle(
                              fontSize: 18,
                              color: theme.textTheme.bodySmall?.color)),
                      const SizedBox(height: 8),
                      if (widget.canUpload)
                        ElevatedButton.icon(
                          onPressed: _uploadMemory,
                          icon: const Icon(Icons.add_photo_alternate,
                              size: 18),
                          label: const Text('Add First Memory'),
                        ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchMemories,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 3,
                      mainAxisSpacing: 3,
                    ),
                    itemCount: _memories.length,
                    itemBuilder: (context, index) {
                      final memory = _memories[index];
                      return GestureDetector(
                        onTap: () => _showFullScreen(memory),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: memory['media_url'] ?? '',
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                  color: theme.colorScheme.surface),
                              errorWidget: (_, __, ___) => Container(
                                color: theme.colorScheme.surface,
                                child: const Icon(
                                    Icons.broken_image_outlined),
                              ),
                            ),
                            if (memory['media_type'] == 'video')
                              const Center(
                                  child: Icon(
                                      Icons.play_circle_filled,
                                      size: 32,
                                      color: Colors.white)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: widget.canUpload && _memories.isNotEmpty
          ? FloatingActionButton(
              onPressed: _isUploading ? null : _uploadMemory,
              backgroundColor: AppTheme.primaryColor,
              child: _isUploading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.add_photo_alternate,
                      color: Colors.black),
            )
          : null,
    );
  }
}

class _FullScreenMemory extends StatelessWidget {
  final Map<String, dynamic> memory;

  const _FullScreenMemory({required this.memory});

  @override
  Widget build(BuildContext context) {
    final userName = memory['user_name'] ?? 'Unknown';
    final profileImage = memory['user_profile_image']?.toString();
    final caption = memory['caption']?.toString() ?? '';
    final createdAt = memory['created_at'] != null
        ? DateTime.tryParse(memory['created_at'].toString())
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage:
                  profileImage != null && profileImage.isNotEmpty
                      ? CachedNetworkImageProvider(profileImage)
                      : null,
              child: profileImage == null || profileImage.isEmpty
                  ? Text(
                      userName.isNotEmpty
                          ? userName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 12))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(userName,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  if (createdAt != null)
                    Text(timeago.format(createdAt),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[400])),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: memory['media_url'] ?? '',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          if (caption.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Text(caption,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14)),
            ),
        ],
      ),
    );
  }
}
