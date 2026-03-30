import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../providers/community_provider.dart';

class CreateSubGroupScreen extends ConsumerStatefulWidget {
  final String communityId;

  const CreateSubGroupScreen({super.key, required this.communityId});

  @override
  ConsumerState<CreateSubGroupScreen> createState() =>
      _CreateSubGroupScreenState();
}

class _CreateSubGroupScreenState
    extends ConsumerState<CreateSubGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedType = 'general';
  bool _isLoading = false;

  static const _types = [
    {'value': 'gym', 'label': 'Gym', 'icon': Icons.fitness_center},
    {'value': 'trip', 'label': 'Trip', 'icon': Icons.flight},
    {'value': 'meetup', 'label': 'Meetup', 'icon': Icons.handshake},
    {'value': 'online_meet', 'label': 'Online Meet', 'icon': Icons.videocam},
    {'value': 'general', 'label': 'General', 'icon': Icons.group},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await ref
          .read(subGroupsProvider(widget.communityId).notifier)
          .createGroup(
            name: _nameController.text.trim(),
            description: _descriptionController.text.trim(),
            type: _selectedType,
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
        title: const Text('Create Group'),
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
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Group Name',
                    prefixIcon: Icon(Icons.group_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Description',
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.description_outlined),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a description';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Group Type',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _types.map((type) {
                    final isSelected = _selectedType == type['value'];
                    return ChoiceChip(
                      avatar: Icon(
                        type['icon'] as IconData,
                        size: 18,
                        color: isSelected ? Colors.black : Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                      ),
                      label: Text(type['label'] as String),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryColor,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.black : Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                      ),
                      onSelected: (_) {
                        setState(
                            () => _selectedType = type['value'] as String);
                      },
                    );
                  }).toList(),
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
                        : const Text('Create Group'),
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
