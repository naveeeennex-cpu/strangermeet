import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../providers/reel_provider.dart';

class CreateReelScreen extends ConsumerStatefulWidget {
  const CreateReelScreen({super.key});

  @override
  ConsumerState<CreateReelScreen> createState() => _CreateReelScreenState();
}

class _CreateReelScreenState extends ConsumerState<CreateReelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mediaUrlController = TextEditingController();
  final _captionController = TextEditingController();
  String _mediaType = 'image';
  bool _isLoading = false;

  @override
  void dispose() {
    _mediaUrlController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(reelsProvider.notifier).createReel(
            mediaUrl: _mediaUrlController.text.trim(),
            caption: _captionController.text.trim(),
            mediaType: _mediaType,
          );

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Reel'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _mediaUrlController,
                  decoration: const InputDecoration(
                    hintText: 'Media URL',
                    prefixIcon: Icon(Icons.link),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a media URL';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _captionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Write a caption...',
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.text_fields),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a caption';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Media Type',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        avatar: Icon(
                          Icons.image,
                          size: 18,
                          color: _mediaType == 'image'
                              ? Colors.black
                              : AppTheme.textSecondary,
                        ),
                        label: const Text('Image'),
                        selected: _mediaType == 'image',
                        selectedColor: AppTheme.primaryColor,
                        backgroundColor: AppTheme.surfaceColor,
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _mediaType == 'image'
                              ? Colors.black
                              : AppTheme.textSecondary,
                        ),
                        onSelected: (_) {
                          setState(() => _mediaType = 'image');
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ChoiceChip(
                        avatar: Icon(
                          Icons.videocam,
                          size: 18,
                          color: _mediaType == 'video'
                              ? Colors.black
                              : AppTheme.textSecondary,
                        ),
                        label: const Text('Video'),
                        selected: _mediaType == 'video',
                        selectedColor: AppTheme.primaryColor,
                        backgroundColor: AppTheme.surfaceColor,
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _mediaType == 'video'
                              ? Colors.black
                              : AppTheme.textSecondary,
                        ),
                        onSelected: (_) {
                          setState(() => _mediaType = 'video');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _create,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text('Create Reel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
