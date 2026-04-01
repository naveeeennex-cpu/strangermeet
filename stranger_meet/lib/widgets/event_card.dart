import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/event.dart';

class EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback? onTap;
  final VoidCallback? onJoin;

  const EventCard({
    super.key,
    required this.event,
    this.onTap,
    this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final slotsRemaining = event.slots > 0
        ? event.slots - event.participantsCount
        : -1; // -1 means unlimited

    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
    final secondaryColor = Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event image
            _buildImage(context),
            // Event details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    event.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // Date row
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: secondaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEE, MMM dd - hh:mm a')
                            .format(event.date),
                        style: TextStyle(
                          fontSize: 13,
                          color: secondaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Location row
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: secondaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.location,
                          style: TextStyle(
                            fontSize: 13,
                            color: secondaryColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Bottom row: price badge + slots + join button
                  Row(
                    children: [
                      // Price badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          event.price > 0
                              ? '\$${event.price.toStringAsFixed(0)}'
                              : 'Free',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Slots remaining
                      if (slotsRemaining >= 0) ...[
                        Icon(
                          Icons.people_outline,
                          size: 16,
                          color: slotsRemaining <= 5
                              ? AppTheme.errorColor
                              : secondaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          slotsRemaining == 0
                              ? 'Full'
                              : '$slotsRemaining spots left',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: slotsRemaining <= 5
                                ? AppTheme.errorColor
                                : secondaryColor,
                          ),
                        ),
                      ],
                      const Spacer(),
                      // Join button
                      SizedBox(
                        height: 36,
                        child: ElevatedButton(
                          onPressed:
                              slotsRemaining == 0 ? null : onJoin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          child: Text(
                            slotsRemaining == 0 ? 'Full' : 'Join',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final secondaryColor = Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    if (event.imageUrl != null) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(16),
        ),
        child: CachedNetworkImage(
          imageUrl: event.imageUrl!,
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            height: 180,
            color: surfaceColor,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            height: 180,
            color: surfaceColor,
            child: Icon(
              Icons.event,
              size: 48,
              color: secondaryColor,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.15),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(16),
        ),
      ),
      child: Icon(
        Icons.event,
        size: 64,
        color: secondaryColor,
      ),
    );
  }
}
