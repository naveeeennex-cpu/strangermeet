import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../models/user.dart';
import '../../models/community.dart';
import '../../providers/admin_provider.dart';
import '../../providers/community_provider.dart';

class CommunityManageScreen extends ConsumerStatefulWidget {
  final String communityId;

  const CommunityManageScreen({super.key, required this.communityId});

  @override
  ConsumerState<CommunityManageScreen> createState() =>
      _CommunityManageScreenState();
}

class _CommunityManageScreenState
    extends ConsumerState<CommunityManageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _memberSearchController = TextEditingController();
  bool _isPrivate = false;
  bool _isEditLoading = false;
  List<User> _members = [];
  List<User> _filteredMembers = [];
  bool _isMembersLoading = false;
  String? _communityImageUrl;

  List<Map<String, dynamic>> _adminEvents = [];
  bool _isAdminEventsLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _memberSearchController.addListener(_filterMembers);
    _loadData();
  }

  void _filterMembers() {
    final query = _memberSearchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredMembers = _members;
      } else {
        _filteredMembers = _members
            .where((m) =>
                m.name.toLowerCase().contains(query) ||
                m.email.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  Future<void> _loadData() async {
    try {
      final detail =
          ref.read(communityDetailProvider(widget.communityId).notifier);
      await detail.fetchCommunity();

      final community =
          ref.read(communityDetailProvider(widget.communityId)).community;
      if (community != null && mounted) {
        _nameController.text = community.name;
        _descriptionController.text = community.description;
        _isPrivate = community.isPrivate;
        _communityImageUrl = community.imageUrl;
      }
    } catch (e) {
      debugPrint('ERROR loading community detail: $e');
    }

    _loadMembers();
    _loadAdminEvents();

    try {
      ref
          .read(subGroupsProvider(widget.communityId).notifier)
          .fetchGroups();
    } catch (e) {
      debugPrint('ERROR loading groups: $e');
    }
  }

  Future<void> _loadMembers() async {
    if (mounted) setState(() => _isMembersLoading = true);
    try {
      final members = await ref
          .read(adminCommunitiesProvider.notifier)
          .fetchMembers(widget.communityId);
      if (mounted) {
        setState(() {
          _members = members;
          _filteredMembers = members;
          _isMembersLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ERROR loading members: $e');
      if (mounted) {
        setState(() => _isMembersLoading = false);
      }
    }
  }

  Future<void> _loadAdminEvents() async {
    if (mounted) setState(() => _isAdminEventsLoading = true);
    try {
      final events = await ref
          .read(adminCommunitiesProvider.notifier)
          .fetchEvents(widget.communityId);
      if (mounted) {
        setState(() {
          _adminEvents = events;
          _isAdminEventsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ERROR loading events: $e');
      if (mounted) {
        setState(() => _isAdminEventsLoading = false);
      }
    }
  }

  Future<void> _saveDetails() async {
    setState(() => _isEditLoading = true);
    try {
      await ref
          .read(adminCommunitiesProvider.notifier)
          .editCommunity(widget.communityId, {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'is_private': _isPrivate,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Community updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isEditLoading = false);
    }
  }

  void _showCreateEventSheet({Map<String, dynamic>? existing}) {
    final titleCtrl =
        TextEditingController(text: existing?['title']?.toString() ?? '');
    final descCtrl = TextEditingController(
        text: existing?['description']?.toString() ?? '');
    final locationCtrl = TextEditingController(
        text: existing?['location']?.toString() ?? '');
    final priceCtrl = TextEditingController(
        text: existing != null ? (existing['price'] ?? 0).toString() : '0');
    final slotsCtrl = TextEditingController(
        text: existing != null ? (existing['slots'] ?? 0).toString() : '0');
    final imageUrlCtrl = TextEditingController(
        text: existing?['image_url']?.toString() ?? '');

    DateTime selectedDate = existing != null && existing['date'] != null
        ? (existing['date'] is DateTime
            ? existing['date']
            : DateTime.tryParse(existing['date'].toString()) ?? DateTime.now())
        : DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(selectedDate);

    String selectedEventType = existing?['event_type']?.toString() ?? 'event';

    final isEdit = existing != null;
    final eventId = existing?['id']?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEdit ? 'Edit Event' : 'Create Event',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Event type toggle
                    Row(
                      children: [
                        Expanded(
                          child: _EventTypeChip(
                            label: 'Event',
                            icon: Icons.event,
                            isSelected: selectedEventType == 'event',
                            onTap: () => setSheetState(
                                () => selectedEventType = 'event'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _EventTypeChip(
                            label: 'Trip',
                            icon: Icons.terrain,
                            isSelected: selectedEventType == 'trip',
                            onTap: () => setSheetState(
                                () => selectedEventType = 'trip'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        prefixIcon: Icon(Icons.title),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(bottom: 24),
                          child: Icon(Icons.description_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setSheetState(() => selectedDate = DateTime(
                                      picked.year,
                                      picked.month,
                                      picked.day,
                                      selectedTime.hour,
                                      selectedTime.minute,
                                    ));
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Date',
                                prefixIcon: Icon(Icons.calendar_today),
                              ),
                              child: Text(
                                DateFormat('MMM d, yyyy')
                                    .format(selectedDate),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: ctx,
                                initialTime: selectedTime,
                              );
                              if (picked != null) {
                                setSheetState(() {
                                  selectedTime = picked;
                                  selectedDate = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Time',
                                prefixIcon: Icon(Icons.access_time),
                              ),
                              child: Text(selectedTime.format(ctx)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Price',
                              prefixIcon: Icon(Icons.currency_rupee),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: slotsCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Slots',
                              prefixIcon: Icon(Icons.people_outline),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: imageUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Image URL (optional)',
                        prefixIcon: Icon(Icons.image_outlined),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final data = {
                            'title': titleCtrl.text.trim(),
                            'description': descCtrl.text.trim(),
                            'location': locationCtrl.text.trim(),
                            'date': selectedDate.toUtc().toIso8601String(),
                            'price': double.tryParse(priceCtrl.text) ?? 0,
                            'slots': int.tryParse(slotsCtrl.text) ?? 0,
                            'image_url': imageUrlCtrl.text.trim(),
                            'event_type': selectedEventType,
                          };

                          try {
                            if (isEdit && eventId != null) {
                              await ref
                                  .read(adminCommunitiesProvider.notifier)
                                  .updateEvent(
                                      widget.communityId, eventId, data);
                            } else {
                              await ref
                                  .read(adminCommunitiesProvider.notifier)
                                  .createEvent(widget.communityId, data);
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            _loadAdminEvents();
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          }
                        },
                        child: Text(isEdit ? 'Update' : 'Create'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDeleteEventDialog(String eventId, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Delete "$title"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(adminCommunitiesProvider.notifier)
                    .deleteEvent(widget.communityId, eventId);
                _loadAdminEvents();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog({SubGroup? existing}) {
    final nameCtrl =
        TextEditingController(text: existing?.name ?? '');
    final descCtrl =
        TextEditingController(text: existing?.description ?? '');
    final isEdit = existing != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Group' : 'Create Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Group Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final desc = descCtrl.text.trim();
              if (name.isEmpty) return;

              try {
                if (isEdit) {
                  await ref
                      .read(adminCommunitiesProvider.notifier)
                      .updateGroup(
                          widget.communityId, existing.id, name, desc);
                } else {
                  await ref
                      .read(adminCommunitiesProvider.notifier)
                      .createGroup(widget.communityId, name, desc);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                ref
                    .read(subGroupsProvider(widget.communityId).notifier)
                    .fetchGroups();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
            child: Text(isEdit ? 'Update' : 'Create'),
          ),
        ],
      ),
    );
  }

  void _showDeleteGroupDialog(SubGroup group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Delete "${group.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(adminCommunitiesProvider.notifier)
                    .deleteGroup(widget.communityId, group.id);
                ref
                    .read(subGroupsProvider(widget.communityId).notifier)
                    .fetchGroups();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _memberSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Community'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
          unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
          indicatorColor: AppTheme.primaryColor,
          indicatorWeight: 3,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Details'),
            Tab(text: 'Members'),
            Tab(text: 'Groups'),
            Tab(text: 'Events'),
          ],
        ),
      ),
      floatingActionButton: _buildFab(),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDetailsTab(),
          _buildMembersTab(),
          _buildGroupsTab(),
          _buildEventsTab(),
        ],
      ),
    );
  }

  Widget? _buildFab() {
    return ListenableBuilder(
      listenable: _tabController,
      builder: (context, _) {
        final index = _tabController.index;
        if (index == 2) {
          return FloatingActionButton(
            backgroundColor: AppTheme.primaryColor,
            onPressed: () => _showCreateGroupDialog(),
            child: const Icon(Icons.add, color: Colors.black),
          );
        } else if (index == 3) {
          return FloatingActionButton(
            backgroundColor: AppTheme.primaryColor,
            onPressed: () => _showCreateEventSheet(),
            child: const Icon(Icons.add, color: Colors.black),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  // ---- Details Tab ----
  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Community image preview
          if (_communityImageUrl != null && _communityImageUrl!.isNotEmpty)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: _communityImageUrl!,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    height: 180,
                    color: Colors.grey[200],
                    child: const Icon(Icons.image, size: 48, color: Colors.grey),
                  ),
                ),
              ),
            )
          else
            Center(
              child: Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_outlined, size: 40, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text('No image set', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'Community Name',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.group_outlined),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Description',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 48),
                child: Icon(Icons.description_outlined),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline, size: 20, color: Colors.grey[600]),
                    const SizedBox(width: 10),
                    const Text(
                      'Private Community',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _isPrivate,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (val) => setState(() => _isPrivate = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isEditLoading ? null : _saveDetails,
              child: _isEditLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text('Save Changes'),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Members Tab ----
  Widget _buildMembersTab() {
    if (_isMembersLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _memberSearchController,
            decoration: InputDecoration(
              hintText: 'Search members...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _memberSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _memberSearchController.clear();
                      },
                    )
                  : null,
            ),
          ),
        ),
        // Member count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '${_filteredMembers.length} member${_filteredMembers.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _filteredMembers.isEmpty
              ? Center(
                  child: Text(
                    _memberSearchController.text.isNotEmpty
                        ? 'No members match your search'
                        : 'No members',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredMembers.length,
                  itemBuilder: (context, index) {
                    final member = _filteredMembers[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          backgroundImage: member.profileImageUrl != null
                              ? CachedNetworkImageProvider(
                                  member.profileImageUrl!)
                              : null,
                          child: member.profileImageUrl == null
                              ? Text(
                                  member.name.isNotEmpty
                                      ? member.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                member.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Role badge - show Admin if it's the first member (creator)
                            if (index == 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Admin',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Member',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          member.email,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                          ),
                        ),
                        trailing: index == 0
                            ? null
                            : IconButton(
                                icon: Icon(
                                  Icons.person_remove_outlined,
                                  color: AppTheme.errorColor,
                                  size: 20,
                                ),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Remove Member'),
                                      content: Text(
                                          'Remove ${member.name} from this community?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            Navigator.pop(ctx);
                                            await ref
                                                .read(
                                                    adminCommunitiesProvider
                                                        .notifier)
                                                .kickMember(
                                                    widget.communityId,
                                                    member.id);
                                            _loadMembers();
                                          },
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                AppTheme.errorColor,
                                          ),
                                          child: const Text('Remove'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---- Groups Tab ----
  Widget _buildGroupsTab() {
    return Consumer(
      builder: (context, ref, _) {
        final groupsState =
            ref.watch(subGroupsProvider(widget.communityId));
        if (groupsState.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (groupsState.groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.group_work_outlined,
                    size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text('No groups yet',
                    style: TextStyle(color: Colors.grey[500])),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _showCreateGroupDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create Group'),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groupsState.groups.length,
          itemBuilder: (context, index) {
            final group = groupsState.groups[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              AppTheme.primaryColor.withOpacity(0.2),
                          child: Icon(Icons.group,
                              color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      group.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Type badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      group.type,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${group.membersCount} members',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Private/Public toggle
                        Column(
                          children: [
                            GestureDetector(
                              onTap: () async {
                                try {
                                  await ref
                                      .read(adminCommunitiesProvider
                                          .notifier)
                                      .toggleGroupPrivate(
                                          widget.communityId, group.id);
                                  ref
                                      .read(subGroupsProvider(
                                              widget.communityId)
                                          .notifier)
                                      .fetchGroups();
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                          content: Text(e.toString())),
                                    );
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: group.isPrivate
                                      ? Colors.orange[50]
                                      : Colors.green[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: group.isPrivate
                                        ? Colors.orange.shade200
                                        : Colors.green.shade200,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      group.isPrivate
                                          ? Icons.lock
                                          : Icons.lock_open,
                                      size: 14,
                                      color: group.isPrivate
                                          ? Colors.orange[700]
                                          : Colors.green[700],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      group.isPrivate
                                          ? 'Private'
                                          : 'Public',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: group.isPrivate
                                            ? Colors.orange[700]
                                            : Colors.green[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18),
                                onPressed: () => _showCreateGroupDialog(
                                    existing: group),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    size: 18,
                                    color: AppTheme.errorColor),
                                onPressed: () =>
                                    _showDeleteGroupDialog(group),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                              ),
                            ],
                          ),
                        ),
                        if (group.isPrivate)
                          GestureDetector(
                            onTap: () => _showPendingRequestsDialog(group),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.amber[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.pending_actions,
                                      size: 14, color: Colors.amber[800]),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Requests',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.amber[800],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPendingRequestsDialog(SubGroup group) async {
    List<Map<String, dynamic>> requests = [];
    bool isLoading = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (isLoading) {
              ref
                  .read(adminCommunitiesProvider.notifier)
                  .fetchPendingRequests(widget.communityId, group.id)
                  .then((result) {
                setDialogState(() {
                  requests = result;
                  isLoading = false;
                });
              }).catchError((_) {
                setDialogState(() => isLoading = false);
              });
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(child: Text('Pending Requests')),
                  if (!isLoading)
                    Text(
                      '${requests.length}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: isLoading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : requests.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No pending requests'),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: requests.length,
                            itemBuilder: (ctx, index) {
                              final req = requests[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.surface,
                                  backgroundImage:
                                      req['user_profile_image'] != null
                                          ? CachedNetworkImageProvider(
                                              req['user_profile_image'])
                                          : null,
                                  child: req['user_profile_image'] == null
                                      ? Text(
                                          (req['user_name'] ?? '?')[0]
                                              .toUpperCase(),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                        )
                                      : null,
                                ),
                                title: Text(
                                  req['user_name'] ?? 'Unknown',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                          Icons.check_circle,
                                          color: Colors.green),
                                      onPressed: () async {
                                        try {
                                          await ref
                                              .read(
                                                  adminCommunitiesProvider
                                                      .notifier)
                                              .approveJoinRequest(
                                                  widget.communityId,
                                                  group.id,
                                                  req['user_id']);
                                          setDialogState(() {
                                            requests.removeAt(index);
                                          });
                                          ref
                                              .read(subGroupsProvider(
                                                      widget.communityId)
                                                  .notifier)
                                              .fetchGroups();
                                        } catch (e) {
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(ctx)
                                                .showSnackBar(SnackBar(
                                                    content: Text(
                                                        e.toString())));
                                          }
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.cancel,
                                          color: Colors.red[400]),
                                      onPressed: () async {
                                        try {
                                          await ref
                                              .read(
                                                  adminCommunitiesProvider
                                                      .notifier)
                                              .rejectJoinRequest(
                                                  widget.communityId,
                                                  group.id,
                                                  req['user_id']);
                                          setDialogState(() {
                                            requests.removeAt(index);
                                          });
                                        } catch (e) {
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(ctx)
                                                .showSnackBar(SnackBar(
                                                    content: Text(
                                                        e.toString())));
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---- Events Tab ----
  Widget _buildEventsTab() {
    if (_isAdminEventsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_adminEvents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_outlined,
                size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No events yet',
                style: TextStyle(color: Colors.grey[500])),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showCreateEventSheet(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create Event'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Split into upcoming and past based on date
    final now = DateTime.now();
    final upcomingEvents = _adminEvents.where((e) {
      final dateStr = e['date']?.toString();
      if (dateStr == null) return true;
      final date = DateTime.tryParse(dateStr);
      return date == null || date.isAfter(now);
    }).toList();
    final pastEvents = _adminEvents.where((e) {
      final dateStr = e['date']?.toString();
      if (dateStr == null) return false;
      final date = DateTime.tryParse(dateStr);
      return date != null && date.isBefore(now);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadAdminEvents,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Upcoming section
          if (upcomingEvents.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Upcoming (${upcomingEvents.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.green[700],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...upcomingEvents.map((e) => _buildAdminEventCard(e, isPast: false)),
          ],

          // Past section
          if (pastEvents.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Past Events (${pastEvents.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...pastEvents.map((e) => _buildAdminEventCard(e, isPast: true)),
          ],
        ],
      ),
    );
  }

  Widget _buildAdminEventCard(Map<String, dynamic> event, {required bool isPast}) {
    final title = event['title']?.toString() ?? 'Untitled';
    final enrolled = event['enrolled_count'] ?? 0;
    final slots = event['slots'] ?? 0;
    final price = (event['price'] ?? 0).toDouble();
    final location = event['location']?.toString() ?? '';
    final dateStr = event['date']?.toString();
    final eventDate = dateStr != null ? DateTime.tryParse(dateStr) : null;
    final progress = slots > 0 ? (enrolled / slots).clamp(0.0, 1.0) : 0.0;
    final eventId = event['id']?.toString() ?? '';
    final eventType = event['event_type']?.toString() ?? 'event';
    final isTrip = eventType == 'trip';
    final imageUrl = event['image_url']?.toString() ?? '';

    return Opacity(
      opacity: isPast ? 0.7 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isPast ? Colors.grey.shade300 : Colors.grey.shade200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image thumbnail
            if (imageUrl.isNotEmpty)
              SizedBox(
                height: 100,
                width: double.infinity,
                child: ColorFiltered(
                  colorFilter: isPast
                      ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                      : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isTrip ? Colors.teal[50] : Colors.indigo[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isTrip ? Icons.terrain : Icons.event,
                              size: 12,
                              color: isTrip ? Colors.teal[700] : Colors.indigo[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isTrip ? 'Trip' : 'Event',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isTrip ? Colors.teal[700] : Colors.indigo[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isPast) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Completed',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _showCreateEventSheet(existing: event);
                          } else if (value == 'delete') {
                            _showDeleteEventDialog(eventId, title);
                          } else if (value == 'enrollments') {
                            context.push(
                              '/partner/community/${widget.communityId}/event/$eventId/enrollments',
                            );
                          } else if (value == 'manage_trip') {
                            context.push(
                              '/partner/community/${widget.communityId}/trip/$eventId/manage',
                            );
                          }
                        },
                        itemBuilder: (ctx) => [
                          if (isTrip)
                            const PopupMenuItem(
                              value: 'manage_trip',
                              child: Row(
                                children: [
                                  Icon(Icons.terrain, size: 18),
                                  SizedBox(width: 8),
                                  Text('Manage Trip'),
                                ],
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'enrollments',
                            child: Row(
                              children: [
                                Icon(Icons.people_outline, size: 18),
                                SizedBox(width: 8),
                                Text('View Enrollments'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline,
                                    size: 18, color: AppTheme.errorColor),
                                const SizedBox(width: 8),
                                Text('Delete',
                                    style:
                                        TextStyle(color: AppTheme.errorColor)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (eventDate != null) ...[
                        Icon(Icons.calendar_today,
                            size: 13, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('MMM d, yyyy').format(eventDate),
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (location.isNotEmpty) ...[
                        Icon(Icons.location_on_outlined,
                            size: 13, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            location,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: price > 0
                              ? Colors.green[50]
                              : AppTheme.primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          price > 0
                              ? '\u20B9${price.toStringAsFixed(0)}'
                              : 'FREE',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: price > 0 ? Colors.green[700] : Colors.black87,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        isPast
                            ? '$enrolled attended'
                            : '$enrolled/$slots enrolled',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isPast ? Colors.grey : AppTheme.primaryColor,
                      ),
                      minHeight: 6,
                    ),
                  ),
                  if (isTrip && !isPast) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          context.push(
                            '/partner/community/${widget.communityId}/trip/$eventId/manage',
                          );
                        },
                        icon: const Icon(Icons.terrain, size: 16),
                        label: const Text('Manage Trip'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _EventTypeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withOpacity(0.2) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.black : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.black : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
