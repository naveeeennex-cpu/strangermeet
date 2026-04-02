import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/websocket_service.dart';
import 'otp_verification_screen.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 4;

  // Google sign-up state
  bool _isGoogleSignup = false;
  String _googleId = '';
  String _googlePictureUrl = '';
  bool _isEmailVerified = false;
  bool _isGoogleLoading = false;

  // Step 1 - Basic Info
  final _step1FormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Username availability
  final _usernameRegex = RegExp(r'^[a-z0-9_.]+$');
  bool? _isUsernameAvailable;
  bool _isCheckingUsername = false;
  Timer? _usernameDebounce;

  // Step 2 - About You
  String _occupation = '';
  String _designation = '';
  final _customDesignationController = TextEditingController();
  final _collegeController = TextEditingController();
  final _companyController = TextEditingController();

  static const _designations = [
    'Software Developer',
    'Designer',
    'Entrepreneur',
    'HR',
    'Journalist',
    'Marketing',
    'Finance',
    'Content Creator',
    'Freelancer',
    'Teacher / Professor',
    'Doctor / Healthcare',
    'Lawyer',
    'Engineer',
    'Sales',
    'Consultant',
    'Data Analyst',
    'Product Manager',
    'Other',
  ];

  // Step 3 - Interests
  final List<String> _allInterests = [
    'Travel',
    'Food',
    'Music',
    'Sports',
    'Fitness',
    'Photography',
    'Art',
    'Technology',
    'Movies',
    'Reading',
    'Gaming',
    'Nature',
    'Cooking',
    'Dance',
    'Singing',
    'Adventure',
    'Cycling',
    'Swimming',
  ];
  final Set<String> _selectedInterests = {};

  // Step 4 - Profile Photo
  File? _profileImage;
  String? _uploadedImageUrl;
  bool _isUploadingImage = false;

  bool _isSigningUp = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill if coming from Google sign-in
    final googleData = ref.read(authStateProvider).pendingGoogleData;
    if (googleData != null && googleData['is_new_user'] == true) {
      _nameController.text = googleData['name'] ?? '';
      _emailController.text = googleData['email'] ?? '';
      _googleId = googleData['google_id'] ?? '';
      _googlePictureUrl = googleData['picture'] ?? '';
      _isGoogleSignup = true;
      _isEmailVerified = true; // Google already verified the email
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _collegeController.dispose();
    _companyController.dispose();
    _customDesignationController.dispose();
    _usernameDebounce?.cancel();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _usernameDebounce?.cancel();
    final trimmed = value.trim().toLowerCase();
    if (trimmed.length < 3 || !_usernameRegex.hasMatch(trimmed)) {
      setState(() {
        _isUsernameAvailable = null;
        _isCheckingUsername = false;
      });
      return;
    }
    setState(() => _isCheckingUsername = true);
    _usernameDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final response =
            await ApiService().get('/auth/check-username/$trimmed');
        if (mounted) {
          setState(() {
            _isUsernameAvailable = response.data['available'] == true;
            _isCheckingUsername = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _isUsernameAvailable = null;
            _isCheckingUsername = false;
          });
        }
      }
    });
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (!_step1FormKey.currentState!.validate()) return;
      if (_isUsernameAvailable == false) return;

      // For regular signup: verify email via OTP before proceeding
      if (!_isGoogleSignup && !_isEmailVerified) {
        final email = _emailController.text.trim();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
              email: email,
              onVerified: () {
                Navigator.pop(context);
                setState(() => _isEmailVerified = true);
                _goToStep(1);
              },
            ),
          ),
        );
        return;
      }
    }
    if (_currentStep == 2) {
      if (_selectedInterests.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least 3 interests')),
        );
        return;
      }
    }
    if (_currentStep < _totalSteps - 1) {
      _goToStep(_currentStep + 1);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    await ref.read(authStateProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    setState(() => _isGoogleLoading = false);

    final state = ref.read(authStateProvider);
    if (state.status == AuthStatus.authenticated) {
      // Existing Google user — logged in
      WebSocketService().connect();
      if (state.user?.role == 'partner') {
        context.go('/partner');
      } else {
        context.go('/explore');
      }
    } else if (state.status == AuthStatus.needsOnboarding) {
      // New Google user — pre-fill and continue
      final googleData = state.pendingGoogleData!;
      setState(() {
        _nameController.text = googleData['name'] ?? '';
        _emailController.text = googleData['email'] ?? '';
        _googleId = googleData['google_id'] ?? '';
        _googlePictureUrl = googleData['picture'] ?? '';
        _isGoogleSignup = true;
        _isEmailVerified = true;
      });
    } else if (state.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.errorMessage!)),
      );
      ref.read(authStateProvider.notifier).clearError();
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() {
      _profileImage = File(picked.path);
      _isUploadingImage = true;
    });

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(picked.path),
        'folder': 'profiles',
      });
      final response = await ApiService().uploadFile(
        '/api/upload',
        formData: formData,
      );
      if (mounted) {
        setState(() {
          _uploadedImageUrl = response.data['url'] as String?;
          _isUploadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e')),
        );
      }
    }
  }

  Future<void> _signup() async {
    setState(() => _isSigningUp = true);

    await ref.read(authStateProvider.notifier).signup(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _isGoogleSignup ? null : _passwordController.text,
          username: _usernameController.text.trim().toLowerCase(),
          interests: _selectedInterests.toList(),
          role: 'customer',
          occupation: _occupation,
          collegeName: _collegeController.text.trim(),
          companyName: _companyController.text.trim(),
          designation: _designation == 'Other'
              ? _customDesignationController.text.trim()
              : _designation,
          googleId: _googleId,
          profileImageUrl: _uploadedImageUrl ?? _googlePictureUrl,
        );

    if (!mounted) return;
    final state = ref.read(authStateProvider);

    if (state.status == AuthStatus.authenticated) {
      if (_uploadedImageUrl != null && _googlePictureUrl.isEmpty) {
        await ref.read(authStateProvider.notifier).updateProfile(
              profileImageUrl: _uploadedImageUrl,
            );
      }
      WebSocketService().connect();
      if (mounted) context.go('/explore');
    } else if (state.errorMessage != null) {
      setState(() => _isSigningUp = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.errorMessage!)),
      );
      ref.read(authStateProvider.notifier).clearError();
    } else {
      setState(() => _isSigningUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildProgressBar(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _currentStep = index);
                },
                children: [
                  _buildStep1BasicInfo(),
                  _buildStep2AboutYou(),
                  _buildStep3Interests(),
                  _buildStep4ProfilePhoto(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (_currentStep > 0)
            GestureDetector(
              onTap: _prevStep,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back, size: 20),
              ),
            )
          else
            GestureDetector(
              onTap: () => context.go('/welcome'),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.close, size: 20),
              ),
            ),
          const Spacer(),
          Row(
            children: List.generate(_totalSteps, (index) {
              final isActive = index == _currentStep;
              final isCompleted = index < _currentStep;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive || isCompleted
                      ? AppTheme.primaryColor
                      : AppTheme.dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const Spacer(),
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = (_currentStep + 1) / _totalSteps;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: AppTheme.dividerColor,
          valueColor:
              const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
          minHeight: 3,
        ),
      ),
    );
  }

  // ======================= STEP 1: Basic Info =======================
  Widget _buildStep1BasicInfo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Form(
        key: _step1FormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            const Text(
              'Create your account',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Fill in your details to get started',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            // Name
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              readOnly: _isGoogleSignup,
              decoration: InputDecoration(
                hintText: 'Full Name',
                prefixIcon: const Icon(Icons.person_outlined),
                suffixIcon: _isGoogleSignup
                    ? const Icon(Icons.lock_outline, size: 18, color: Colors.grey)
                    : null,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Username
            TextFormField(
              controller: _usernameController,
              keyboardType: TextInputType.text,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'Choose a username',
                prefixIcon: const Icon(Icons.alternate_email),
                suffixIcon: _isCheckingUsername
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _isUsernameAvailable == true
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : _isUsernameAvailable == false
                            ? const Icon(Icons.cancel, color: Colors.red)
                            : null,
              ),
              onChanged: _onUsernameChanged,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please choose a username';
                }
                if (value.trim().length < 3) {
                  return 'Username must be at least 3 characters';
                }
                if (value.trim().length > 30) {
                  return 'Username must be at most 30 characters';
                }
                if (!_usernameRegex.hasMatch(value.trim().toLowerCase())) {
                  return 'Only lowercase letters, numbers, _ and . allowed';
                }
                if (_isUsernameAvailable == false) {
                  return 'Username is already taken';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Email
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              readOnly: _isGoogleSignup,
              decoration: InputDecoration(
                hintText: 'Email address',
                prefixIcon: const Icon(Icons.email_outlined),
                suffixIcon: _isEmailVerified
                    ? const Icon(Icons.verified, color: Colors.green)
                    : _isGoogleSignup
                        ? const Icon(Icons.lock_outline, size: 18, color: Colors.grey)
                        : null,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your email';
                }
                if (!value.contains('@')) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            // Password (hidden for Google signup)
            if (!_isGoogleSignup) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                validator: (value) {
                  if (_isGoogleSignup) return null;
                  if (value == null || value.isEmpty) {
                    return 'Please enter a password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 32),
            // Next button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _nextStep,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isEmailVerified ? 'Next' : 'Verify Email & Continue'),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
              ),
            ),
            if (!_isGoogleSignup) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey[700])),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'or',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey[700])),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey[700]!),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isGoogleLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryColor,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/images/google_logo.png',
                              height: 20,
                              width: 20,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.g_mobiledata,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Continue with Google',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Already have an account? ',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                GestureDetector(
                  onTap: () => context.go('/login'),
                  child: const Text(
                    'Login',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ======================= STEP 2: About You =======================
  Widget _buildStep2AboutYou() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const Text(
            'Tell us about yourself',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'What do you do?',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),
          _buildOccupationOption(
            title: 'Student',
            subtitle: 'Currently studying',
            icon: Icons.school_outlined,
            value: 'student',
          ),
          const SizedBox(height: 12),
          _buildOccupationOption(
            title: 'Working Professional',
            subtitle: 'Currently employed',
            icon: Icons.work_outline,
            value: 'working',
          ),
          const SizedBox(height: 24),
          if (_occupation == 'student') ...[
            TextFormField(
              controller: _collegeController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'College / University name',
                prefixIcon: Icon(Icons.account_balance_outlined),
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (_occupation == 'working') ...[
            TextFormField(
              controller: _companyController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Company name',
                prefixIcon: Icon(Icons.business_outlined),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your Role',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _designations.map((role) {
                final isSelected = _designation == role;
                return GestureDetector(
                  onTap: () => setState(() => _designation = role),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor.withOpacity(0.2)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : Theme.of(context).dividerColor,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      role,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected
                            ? AppTheme.primaryColor
                            : Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_designation == 'Other') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _customDesignationController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Enter your role',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _prevStep,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_back, size: 18),
                      SizedBox(width: 8),
                      Text('Back'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _nextStep,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Next'),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() => _occupation = '');
                _nextStep();
              },
              child: Text(
                'Skip for now',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildOccupationOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
  }) {
    final isSelected = _occupation == value;
    return GestureDetector(
      onTap: () => setState(() => _occupation = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.1)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryColor.withOpacity(0.2)
                    : Theme.of(context).cardTheme.color ??
                        Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 24,
                color: isSelected
                    ? Colors.black87
                    : Theme.of(context).textTheme.bodySmall?.color ??
                        Colors.grey,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.black87
                          : Theme.of(context).textTheme.bodyLarge?.color ??
                              Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.primaryColor : AppTheme.dividerColor,
                  width: 2,
                ),
                color: isSelected ? AppTheme.primaryColor : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.black87)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ======================= STEP 3: Interests =======================
  Widget _buildStep3Interests() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const Text(
            'Pick your interests',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Select at least 3 topics you're interested in",
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_selectedInterests.length}/${_allInterests.length} selected',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _selectedInterests.length >= 3
                  ? Colors.green[700]
                  : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _allInterests.map((interest) {
              final isSelected = _selectedInterests.contains(interest);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedInterests.remove(interest);
                    } else {
                      _selectedInterests.add(interest);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.dividerColor,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    interest,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? Colors.black
                          : Theme.of(context).textTheme.bodyLarge?.color ??
                              Colors.black,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _prevStep,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_back, size: 18),
                      SizedBox(width: 8),
                      Text('Back'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _nextStep,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Next'),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ======================= STEP 4: Profile Photo =======================
  Widget _buildStep4ProfilePhoto() {
    // Determine the preview image: uploaded file > Google picture URL
    final hasImage = _profileImage != null || _googlePictureUrl.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Add a profile photo',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Help others recognize you',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 48),
          GestureDetector(
            onTap: _isUploadingImage ? null : _pickImage,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: hasImage
                          ? AppTheme.primaryColor
                          : AppTheme.dividerColor,
                      width: 3,
                    ),
                    image: _profileImage != null
                        ? DecorationImage(
                            image: FileImage(_profileImage!),
                            fit: BoxFit.cover,
                          )
                        : _googlePictureUrl.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(_googlePictureUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                  ),
                  child: !hasImage
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt_outlined,
                              size: 40,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap to upload',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
                if (_isUploadingImage)
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.4),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (hasImage && !_isUploadingImage)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Change photo'),
              ),
            ),
          const SizedBox(height: 48),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSigningUp ? null : _prevStep,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_back, size: 18),
                      SizedBox(width: 8),
                      Text('Back'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSigningUp || _isUploadingImage ? null : _signup,
                  child: _isSigningUp
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Get Started'),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_isSigningUp)
            TextButton(
              onPressed: () {
                setState(() {
                  _profileImage = null;
                  _uploadedImageUrl = null;
                  // Keep Google picture URL as fallback
                });
                _signup();
              },
              child: Text(
                'Skip for now',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
