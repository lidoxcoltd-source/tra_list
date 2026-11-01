import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/chat_presence_service.dart';
import 'package:url_launcher/url_launcher.dart';

import 'push_service.dart';
import 'app_activity_service.dart';
import 'app_version_service.dart';

class AppVersionGate extends StatefulWidget {
  const AppVersionGate({required this.child, super.key});

  final Widget child;

  @override
  State<AppVersionGate> createState() => _AppVersionGateState();
}

class _AppVersionGateState extends State<AppVersionGate>
    with WidgetsBindingObserver {
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<bool>? _businessReadySubscription;
  StreamSubscription<String>? _businessIdSubscription;
  PackageInfo? _packageInfo;
  AppVersionPolicy? _policy;
  PlatformVersionPolicy? _platformPolicy;
  bool _blocked = false;
  int _checkGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _businessReadySubscription = BusinessAccessService.isReady.listen(
      (_) => ChatPresenceService.refresh(),
    );
    _businessIdSubscription = BusinessAccessService.businessUid.listen(
      (_) => ChatPresenceService.refresh(),
    );
    ChatPresenceService.refresh();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _checkVersion,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('App version gate could not observe sign-in state: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _businessReadySubscription?.cancel();
    _businessIdSubscription?.cancel();
    ChatPresenceService.setForeground(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ChatPresenceService.setForeground(true);
      _checkVersion(FirebaseAuth.instance.currentUser);
    } else {
      ChatPresenceService.setForeground(false);
    }
  }

  Future<void> _checkVersion(User? user) async {
    final generation = ++_checkGeneration;
    ChatPresenceService.refresh();
    if (user != null) {
      AppActivityService.ping();
      PushService.register();
    }
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _blocked = false;
      });
      return;
    }

    final platform = AppVersionService.currentPlatform;
    if (platform == null) {
      _setAllowed(generation);
      return;
    }

    try {
      if (await _isSuperAdmin(user)) {
        _setAllowed(generation);
        return;
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Could not verify super admin status for app version gate: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }

    try {
      _packageInfo ??= await AppVersionService.installedPackageInfo();
      final cached = await AppVersionService.loadCachedPolicy();
      if (cached != null) {
        _applyPolicy(generation, platform, cached, _packageInfo!);
      }

      final remote = await AppVersionService.loadRemotePolicy().timeout(
        const Duration(seconds: 8),
      );
      _applyPolicy(generation, platform, remote, _packageInfo!);
    } catch (error, stackTrace) {
      debugPrint('Could not refresh app version policy: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (generation == _checkGeneration && mounted && _policy == null) {
        setState(() {
          _blocked = false;
        });
      }
    }
  }

  Future<bool> _isSuperAdmin(User user) async {
    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('profile')
        .doc('company')
        .get()
        .timeout(const Duration(seconds: 5));
    final role = (profile.data()?['role']?.toString() ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return role == 'superadmin';
  }

  void _applyPolicy(
    int generation,
    String platform,
    AppVersionPolicy policy,
    PackageInfo packageInfo,
  ) {
    if (!mounted || generation != _checkGeneration) return;
    final platformPolicy = policy.forPlatform(platform);
    final blocked = AppVersionService.isUpdateRequired(
      installedVersion: packageInfo.version,
      installedBuild: int.tryParse(packageInfo.buildNumber) ?? 0,
      policy: platformPolicy,
    );
    if (blocked && !_blocked) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() {
      _policy = policy;
      _platformPolicy = platformPolicy;
      _blocked = blocked;
    });
  }

  void _setAllowed(int generation) {
    if (!mounted || generation != _checkGeneration) return;
    setState(() {
      _blocked = false;
    });
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    BusinessAccessService.clear();
    Get.offAllNamed(AppRoutes.login);
  }

  Future<void> _openUpdate() async {
    final url = _platformPolicy?.updateUrl.trim() ?? '';
    final uri = Uri.tryParse(url);
    try {
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No valid update link could be opened.');
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to open app update link: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the update link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the app mounted so its navigation state survives the check.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          ignoring: !_blocked,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ModalBarrier(color: Colors.transparent, dismissible: false),
              Offstage(
                offstage: !_blocked,
                child: _buildUpdateRequired(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUpdateRequired(BuildContext context) {
    final minimumVersion = _platformPolicy?.minimumVersion ?? '';
    final minimumBuild = _platformPolicy?.minimumBuild ?? 0;
    final installed = _packageInfo == null
        ? ''
        : '${_packageInfo!.version}+${_packageInfo!.buildNumber}';
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7F8),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              margin: const EdgeInsets.all(24),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.system_update_alt_rounded,
                      size: 58,
                      color: Color(0xFF0E5962),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Update required',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _policy?.message ??
                          'Please install the latest app version to continue.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Installed: $installed\nRequired: $minimumVersion+$minimumBuild',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openUpdate,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Get the update'),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          _checkVersion(FirebaseAuth.instance.currentUser),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('I have updated — check again'),
                    ),
                    TextButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Log out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
