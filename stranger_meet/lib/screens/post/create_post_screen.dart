import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/theme.dart';
import '../../providers/post_provider.dart';
import '../../services/api_service.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen>
    with SingleTickerProviderStateMixin {
  final _captionController = TextEditingController();
  XFile? _selectedImage;
  Uint8List? _imageBytes;
  XFile? _selectedVideo;
  Uint8List? _videoBytes;
  bool _isSubmitting = false;
  late TabController _tabController;

  // 0 = Post (image), 1 = Reel (video)
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _selectedTab = _tabController.index);
    });
  }

  @override
  void dispose() {
    _captionController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _selectedImage = pickedFile;
        _imageBytes = bytes;
      });
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _selectedVideo = pickedFile;
        _videoBytes = bytes;
      });
    }
  }

  Future<void> _createPost() async {
    final caption = _captionController.text.trim();
    final isReel = _selectedTab == 1;

    if (isReel) {
      if (caption.isEmpty && _selectedVideo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add a caption or video')),
        );
        return;
      }
    } else {
      if (caption.isEmpty && _selectedImage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add a caption or image')),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      if (isReel && _selectedVideo != null && _videoBytes != null) {
        // Upload video + create post
        final formData = FormData.fromMap({
          'caption': caption,
          'media_type': 'video',
          'video': MultipartFile.fromBytes(
            _videoBytes!,
            filename: _selectedVideo!.name,
          ),
        });
        await ApiService().uploadFile('/upload/post', formData: formData);
      } else if (!isReel && _selectedImage != null && _imageBytes != null) {
        // Upload image + create post in one request
        final formData = FormData.fromMap({
          'caption': caption,
          'media_type': 'image',
          'image': MultipartFile.fromBytes(
            _imageBytes!,
            filename: _selectedImage!.name,
          ),
        });
        await ApiService().uploadFile('/upload/post', formData: formData);
      } else {
        // Text-only post
        await ApiService().post('/posts', data: {
          'caption': caption,
          'media_type': 'text',
        });
      }

      // Refresh feed
      await ref.read(postsProvider.notifier).fetchPosts(refresh: true);

      if (mounted) {
        _captionController.clear();
        setState(() {
          _selectedImage = null;
          _imageBytes = null;
          _selectedVideo = null;
          _videoBytes = null;
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isReel
                ? 'Reel created successfully!'
                : 'Post created successfully!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _clearMedia() {
    setState(() {
      _selectedImage = null;
      _imageBytes = null;
      _selectedVideo = null;
      _videoBytes = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isReel = _selectedTab == 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _createPost,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isReel ? 'Share Reel' : 'Post'),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryColor,
          labelColor: Theme.of(context).textTheme.bodyLarge?.color,
          unselectedLabelColor: Colors.grey[500],
          tabs: const [
            Tab(
              icon: Icon(Icons.photo_outlined),
              text: 'Post',
            ),
            Tab(
              icon: Icon(Icons.videocam_outlined),
              text: 'Reel',
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _captionController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: isReel
                    ? 'Add a caption for your reel...'
                    : "What's on your mind?",
                border: InputBorder.none,
                filled: false,
              ),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),

            // Image preview (Post tab)
            if (!isReel && _imageBytes != null) ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      _imageBytes!,
                      width: double.infinity,
                      height: 300,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _clearMedia,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Video preview (Reel tab)
            if (isReel && _selectedVideo != null) ...[
              Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: 300,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam,
                              color: Colors.white54, size: 64),
                          const SizedBox(height: 12),
                          Text(
                            _selectedVideo!.name,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Video ready to upload',
                            style: TextStyle(
                                color: Colors.green[300], fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _clearMedia,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            if (_isSubmitting && (_imageBytes != null || _videoBytes != null))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            const Divider(),

            // Media picker options
            if (!isReel) ...[
              ListTile(
                leading: Icon(Icons.photo_library_outlined,
                    color: AppTheme.primaryColor),
                title: const Text('Add Photo'),
                onTap: _pickImage,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              ListTile(
                leading: Icon(Icons.camera_alt_outlined,
                    color: AppTheme.primaryColor),
                title: const Text('Take Photo'),
                onTap: () async {
                  final picker = ImagePicker();
                  final pickedFile = await picker.pickImage(
                    source: ImageSource.camera,
                    maxWidth: 1080,
                    maxHeight: 1080,
                    imageQuality: 85,
                  );
                  if (pickedFile != null) {
                    final bytes = await pickedFile.readAsBytes();
                    setState(() {
                      _selectedImage = pickedFile;
                      _imageBytes = bytes;
                    });
                  }
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ] else ...[
              ListTile(
                leading: Icon(Icons.video_library_outlined,
                    color: AppTheme.primaryColor),
                title: const Text('Pick Video'),
                subtitle: const Text('Select a video from gallery'),
                onTap: _pickVideo,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              ListTile(
                leading: Icon(Icons.videocam_outlined,
                    color: AppTheme.primaryColor),
                title: const Text('Record Video'),
                subtitle: const Text('Record with camera'),
                onTap: () async {
                  final picker = ImagePicker();
                  final pickedFile = await picker.pickVideo(
                    source: ImageSource.camera,
                    maxDuration: const Duration(minutes: 5),
                  );
                  if (pickedFile != null) {
                    final bytes = await pickedFile.readAsBytes();
                    setState(() {
                      _selectedVideo = pickedFile;
                      _videoBytes = bytes;
                    });
                  }
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
