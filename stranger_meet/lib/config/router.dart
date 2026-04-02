import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/auth/splash_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/auth/welcome_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/main_shell.dart';
import '../screens/home/home_screen.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/reels/reels_screen.dart';
import '../screens/reels/create_reel_screen.dart';
import '../screens/post/create_post_screen.dart';
import '../screens/post/post_detail_screen.dart';
import '../screens/post/video_post_detail_screen.dart';
import '../screens/chat/conversations_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/user_profile_screen.dart';
import '../screens/bookings/my_bookings_screen.dart';
import '../screens/profile/friend_requests_screen.dart';
import '../screens/home/story_viewer_screen.dart';
import '../screens/community/communities_list_screen.dart';
import '../screens/community/community_detail_screen.dart';
import '../screens/community/community_event_detail_screen.dart';
import '../screens/community/community_chat_screen.dart';
import '../screens/community/sub_group_chat_screen.dart';
import '../screens/community/create_community_screen.dart';
import '../screens/community/community_groups_screen.dart';
import '../screens/community/create_sub_group_screen.dart';
import '../screens/partner/partner_shell.dart';
import '../screens/partner/dashboard_screen.dart';
import '../screens/partner/my_communities_screen.dart';
import '../screens/partner/community_manage_screen.dart';
import '../screens/partner/analytics_screen.dart';
import '../screens/partner/payments_screen.dart';
import '../screens/partner/event_enrollments_screen.dart';
import '../screens/partner/trip_manage_screen.dart';
import '../screens/partner/create_trip_screen.dart';
import '../screens/events/event_detail_screen.dart';
import '../screens/community/event_memories_screen.dart';
import '../screens/saved/my_saved_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();
final _partnerShellNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    // Auth routes
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/welcome',
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) => const SignupScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),

    // Customer ShellRoute
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/main',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HomeScreen(),
          ),
        ),
        GoRoute(
          path: '/communities',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: CommunitiesListScreen(),
          ),
        ),
        GoRoute(
          path: '/explore',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ExploreScreen(),
          ),
        ),
        GoRoute(
          path: '/reels',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ReelsScreen(),
          ),
        ),
        GoRoute(
          path: '/conversations',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConversationsScreen(),
          ),
        ),
        GoRoute(
          path: '/bookings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: MyBookingsScreen(),
          ),
        ),
      ],
    ),

    // Profile (standalone — accessible from avatar tap)
    GoRoute(
      path: '/profile',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/saved',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const MySavedScreen(),
    ),

    // Partner ShellRoute
    ShellRoute(
      navigatorKey: _partnerShellNavigatorKey,
      builder: (context, state, child) => PartnerShell(child: child),
      routes: [
        GoRoute(
          path: '/partner',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DashboardScreen(),
          ),
        ),
        GoRoute(
          path: '/partner-communities',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: MyCommunitiesScreen(),
          ),
        ),
        GoRoute(
          path: '/partner-chat',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConversationsScreen(),
          ),
        ),
        GoRoute(
          path: '/partner-analytics',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AnalyticsScreen(),
          ),
        ),
        GoRoute(
          path: '/partner-profile',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ProfileScreen(),
          ),
        ),
      ],
    ),

    // Detail routes (outside shells)
    GoRoute(
      path: '/community/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CommunityDetailScreen(
        communityId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/community/:id/groups',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CommunityGroupsScreen(
        communityId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/community/:id/chat',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CommunityChatScreen(
        communityId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/community/:id/group/:groupId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => SubGroupChatScreen(
        communityId: state.pathParameters['id']!,
        groupId: state.pathParameters['groupId']!,
      ),
    ),
    GoRoute(
      path: '/community/:id/event/:eventId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CommunityEventDetailScreen(
        communityId: state.pathParameters['id']!,
        eventId: state.pathParameters['eventId']!,
      ),
    ),
    GoRoute(
      path: '/create-community',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CreateCommunityScreen(),
    ),
    GoRoute(
      path: '/create-reel',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CreateReelScreen(),
    ),
    GoRoute(
      path: '/create-post',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CreatePostScreen(),
    ),
    GoRoute(
      path: '/create-sub-group/:communityId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CreateSubGroupScreen(
        communityId: state.pathParameters['communityId']!,
      ),
    ),
    GoRoute(
      path: '/friend-requests',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const FriendRequestsScreen(),
    ),
    GoRoute(
      path: '/notifications',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/partner/community/:id/manage',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CommunityManageScreen(
        communityId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/partner/payments',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PaymentsScreen(),
    ),
    GoRoute(
      path: '/partner/community/:cid/event/:eid/enrollments',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => EventEnrollmentsScreen(
        communityId: state.pathParameters['cid']!,
        eventId: state.pathParameters['eid']!,
      ),
    ),
    GoRoute(
      path: '/partner/community/:cid/trip/:eid/manage',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => TripManageScreen(
        communityId: state.pathParameters['cid']!,
        eventId: state.pathParameters['eid']!,
      ),
    ),
    GoRoute(
      path: '/partner/community/:cid/create-trip',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CreateTripScreen(
        communityId: state.pathParameters['cid']!,
        eventType: state.uri.queryParameters['type'] ?? 'trip',
      ),
    ),
    GoRoute(
      path: '/partner/community/:cid/edit-trip/:eid',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CreateTripScreen(
        communityId: state.pathParameters['cid']!,
        eventId: state.pathParameters['eid'],
        eventType: state.uri.queryParameters['type'] ?? 'trip',
      ),
    ),
    GoRoute(
      path: '/event/:eid/memories',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => EventMemoriesScreen(
        eventId: state.pathParameters['eid']!,
        eventTitle: state.uri.queryParameters['title'] ?? 'Memories',
        canUpload: state.uri.queryParameters['canUpload'] == 'true',
      ),
    ),
    GoRoute(
      path: '/post/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => PostDetailScreen(
        postId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/video-post/:postId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => VideoPostDetailScreen(
        postId: state.pathParameters['postId']!,
      ),
    ),
    GoRoute(
      path: '/event/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => EventDetailScreen(
        eventId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/chat/:userId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => ChatScreen(
        userId: state.pathParameters['userId']!,
        userName: state.uri.queryParameters['name'] ?? 'Chat',
      ),
    ),
    GoRoute(
      path: '/edit-profile',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const EditProfileScreen(),
    ),
    GoRoute(
      path: '/user/:userId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => UserProfileScreen(
        userId: state.pathParameters['userId']!,
      ),
    ),
    GoRoute(
      path: '/story/:userId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => StoryViewerScreen(
        userId: state.pathParameters['userId']!,
      ),
    ),
  ],
);
