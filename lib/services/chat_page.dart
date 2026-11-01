import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/staff_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_service.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const _blue = Color(0xFF1565C0);
  static const _canvas = Color(0xFF191D24);
  static const _header = Color(0xFF252A33);
  static const _muted = Color(0xFF9299A4);

  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _navigatingHome = false;

  @override
  void initState() {
    super.initState();
    _markChatsViewed();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openRoom(String id) async {
    unawaited(_markChatsViewed());
    await Get.toNamed(AppRoutes.getChatRoomRoute(id));
  }

  void _goHome() {
    if (_navigatingHome) return;
    _navigatingHome = true;
    Get.offAllNamed(AppRoutes.home);
  }

  Future<void> _markChatsViewed() async {
    try {
      await ChatService.markChatsViewed();
    } catch (error, stackTrace) {
      debugPrint('Could not mark chat messages as viewed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _openGroup() async {
    try {
      final id = await ChatService.getOrCreateBusinessGroup();
      await _openRoom(id);
    } catch (error, stackTrace) {
      debugPrint('Could not open the business group chat: $error');
      debugPrintStack(stackTrace: stackTrace);
      Get.snackbar('error'.tr, '${'chat_open_failed'.tr}: $error');
    }
  }

  Future<void> _openOwnerChat() async {
    try {
      final ownerName = BusinessAccessService.businessName.value.isEmpty
          ? 'chat_business_owner'.tr
          : BusinessAccessService.businessName.value;
      final id = await ChatService.getOrCreateDirectChat(
        otherUid: BusinessAccessService.businessId,
        otherName: ownerName,
      );
      await _openRoom(id);
    } catch (error, stackTrace) {
      debugPrint('Could not open private owner chat: $error');
      debugPrintStack(stackTrace: stackTrace);
      Get.snackbar('error'.tr, '${'chat_open_failed'.tr}: $error');
    }
  }

  Future<void> _startStaffChat() async {
    try {
      final staff = await ChatService.fetchChatStaff();
      if (!mounted) return;
      final selected = await showModalBottomSheet<StaffMember>(
        context: context,
        backgroundColor: _header,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: staff.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'chat_no_staff'.tr,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: ChatService.watchPresence(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'chat_presence_error'.tr,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      );
                    }
                    final now = DateTime.now();
                    final presenceByUid = {
                      for (final document
                          in snapshot.data?.docs ??
                              const <
                                QueryDocumentSnapshot<Map<String, dynamic>>
                              >[])
                        document.id: document.data(),
                    };
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                          child: Text(
                            'chat_new_chat'.tr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        for (final member in staff)
                          Builder(
                            builder: (context) {
                              final presence = presenceByUid[member.id];
                              final lastActiveAt = presence?['lastActiveAt'];
                              final isOnline =
                                  presence?['isOnline'] == true &&
                                  lastActiveAt is Timestamp &&
                                  now.difference(lastActiveAt.toDate()) <=
                                      const Duration(minutes: 2);
                              final lastSeen = lastActiveAt is Timestamp
                                  ? lastActiveAt.toDate()
                                  : null;
                              final lastSeenLabel = lastSeen == null
                                  ? null
                                  : lastSeen.year == now.year &&
                                        lastSeen.month == now.month &&
                                        lastSeen.day == now.day
                                  ? DateFormat.Hm(
                                      Get.locale?.toString(),
                                    ).format(lastSeen)
                                  : DateFormat.MMMd(
                                      Get.locale?.toString(),
                                    ).add_Hm().format(lastSeen);
                              return ListTile(
                                leading: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const CircleAvatar(
                                      backgroundColor: Color(0xFF414955),
                                      child: Icon(
                                        Icons.person_rounded,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    if (isOnline)
                                      Positioned(
                                        right: -1,
                                        bottom: -1,
                                        child: Container(
                                          width: 13,
                                          height: 13,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF22C55E),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: _header,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Text(
                                  member.data['name']?.toString() ??
                                      'chat_staff'.tr,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: isOnline
                                    ? Text(
                                        'chat_online'.tr,
                                        style: const TextStyle(
                                          color: Color(0xFF22C55E),
                                          fontSize: 12,
                                        ),
                                      )
                                    : lastSeenLabel == null
                                    ? null
                                    : Text(
                                        'chat_last_seen'.trParams({
                                          'time': lastSeenLabel,
                                        }),
                                        style: const TextStyle(
                                          color: Color(0xFFADB4BE),
                                          fontSize: 12,
                                        ),
                                      ),
                                onTap: () => Navigator.pop(context, member),
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
        ),
      );
      if (selected == null) return;
      final id = await ChatService.getOrCreateDirectChat(
        otherUid: selected.id,
        otherName: selected.data['name']?.toString() ?? 'chat_staff'.tr,
      );
      await _openRoom(id);
    } catch (error, stackTrace) {
      debugPrint('Could not start staff chat: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar('error'.tr, '${'chat_open_failed'.tr}: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    initializeDateFormatting(Get.locale?.toString());
    if (!BusinessAccessService.hasBusinessAccess) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goHome();
        },
        child: Scaffold(
          backgroundColor: _canvas,
          appBar: AppBar(
            backgroundColor: _header,
            foregroundColor: Colors.white,
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: _goHome,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            titleTextStyle: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            title: Text('chat_title'.tr),
          ),
          body: Center(child: Text('chat_business_required'.tr)),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: _header,
          foregroundColor: Colors.white,
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
          titleSpacing: 0,
          leadingWidth: 52,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _goHome,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text('chat_title'.tr),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: IconButton(
                tooltip: BusinessAccessService.isOwner.value
                    ? 'chat_open_group'.tr
                    : 'chat_new_chat'.tr,
                onPressed: BusinessAccessService.isOwner.value
                    ? _openGroup
                    : _startStaffChat,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFE4484F),
                  foregroundColor: Colors.white,
                  fixedSize: const Size(34, 34),
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.add_rounded, size: 22),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            const _ChatOfflineBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'chat_search'.tr,
                    hintStyle: const TextStyle(color: _muted, fontSize: 12),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: _muted,
                      size: 18,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    filled: true,
                    fillColor: _header,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ChatService.watchConversations(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '${'chat_load_error'.tr}\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: _blue),
                    );
                  }
                  final conversations = snapshot.data!.docs.where((doc) {
                    if (_searchQuery.trim().isEmpty) return true;
                    final data = doc.data();
                    final names = Map<String, dynamic>.from(
                      data['participantNames'] as Map? ?? const {},
                    ).values.join(' ');
                    final searchable =
                        '${data['title'] ?? ''} $names ${data['lastMessage'] ?? ''}'
                            .toLowerCase();
                    return searchable.contains(
                      _searchQuery.trim().toLowerCase(),
                    );
                  }).toList();
                  if (conversations.isEmpty) {
                    if (snapshot.data!.docs.isNotEmpty) {
                      return Center(
                        child: Text(
                          'chat_no_search_results'.tr,
                          style: const TextStyle(color: _muted),
                        ),
                      );
                    }
                    return _ChatEmptyState(
                      onTap: BusinessAccessService.isOwner.value
                          ? _openGroup
                          : _openOwnerChat,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                    itemCount: conversations.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      thickness: .5,
                      indent: 66,
                      color: Color(0xFF2A3039),
                    ),
                    itemBuilder: (context, index) {
                      final doc = conversations[index];
                      return _ConversationTile(
                        data: doc.data(),
                        onTap: () => _openRoom(doc.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatOfflineBanner extends StatefulWidget {
  const _ChatOfflineBanner();

  @override
  State<_ChatOfflineBanner> createState() => _ChatOfflineBannerState();
}

class _ChatOfflineBannerState extends State<_ChatOfflineBanner> {
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool? _isOnline;

  @override
  void initState() {
    super.initState();
    _subscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectivity,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Could not observe chat connectivity: $error');
        debugPrintStack(stackTrace: stackTrace);
        _updateConnectivity(const [ConnectivityResult.none]);
      },
    );
    unawaited(_checkConnectivity());
  }

  Future<void> _checkConnectivity() async {
    try {
      _updateConnectivity(await _connectivity.checkConnectivity());
    } catch (error, stackTrace) {
      debugPrint('Could not check chat connectivity: $error');
      debugPrintStack(stackTrace: stackTrace);
      _updateConnectivity(const [ConnectivityResult.none]);
    }
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    if (!mounted) return;
    final isOnline = results.any((result) => result != ConnectivityResult.none);
    if (_isOnline != isOnline) setState(() => _isOnline = isOnline);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isOnline != false) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      color: const Color(0xFF493A1C),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFFFFD166),
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'chat_offline_banner'.tr,
              style: const TextStyle(color: Color(0xFFFFE7A8), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF303640),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 34,
                color: Color(0xFFE4484F),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'chat_empty_title'.tr,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'chat_empty_description'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFADB4BE), height: 1.45),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.add_comment_outlined),
              label: Text(
                BusinessAccessService.isOwner.value
                    ? 'chat_open_group'.tr
                    : 'chat_owner_private'.tr,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE4484F),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.data, required this.onTap});

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isGroup = data['type'] == 'group';
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final names = Map<String, dynamic>.from(
      data['participantNames'] as Map? ?? const {},
    );
    final participants = List<String>.from(data['memberUids'] as List? ?? []);
    final isOwnerViewingPeerChat =
        BusinessAccessService.isOwner.value &&
        !isGroup &&
        !participants.contains(uid);
    final otherUid = participants.where((id) => id != uid).firstOrNull ?? '';
    final title = isGroup
        ? (data['title']?.toString().trim().isNotEmpty == true
              ? data['title'].toString()
              : 'chat_group'.tr)
        : isOwnerViewingPeerChat
        ? participants
              .map((id) => names[id]?.toString().trim() ?? '')
              .where((name) => name.isNotEmpty)
              .join(' · ')
        : names[otherUid]?.toString() ?? 'chat_private'.tr;
    final lastMessage = data['lastMessage']?.toString() ?? '';
    final lastSenderName =
        names[data['lastSenderUid']]?.toString().trim() ?? '';
    final preview = isOwnerViewingPeerChat && lastMessage.isNotEmpty
        ? '${lastSenderName.isEmpty ? 'chat_staff'.tr : lastSenderName}: $lastMessage'
        : lastMessage;
    final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate();
    final timeLabel = updatedAt == null
        ? ''
        : updatedAt.year == DateTime.now().year &&
              updatedAt.month == DateTime.now().month &&
              updatedAt.day == DateTime.now().day
        ? DateFormat.Hm(Get.locale?.toString()).format(updatedAt)
        : DateFormat.MMMd(Get.locale?.toString()).format(updatedAt);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF303640),
                child: Text(
                  title.isEmpty ? '?' : title.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFD8DDE4),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF2F3F5),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preview.isEmpty ? 'chat_start_conversation'.tr : preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFADB4BE),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (timeLabel.isNotEmpty)
                Text(
                  timeLabel,
                  style: const TextStyle(color: Color(0xFFE16A6F), fontSize: 9),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  static const _headerColor = Color(0xFF111B21);
  static const _pageColor = Color(0xFF0B141A);
  static const _green = Color(0xFF00A884);
  static const _maxAudioBytes = 8 * 1024 * 1024;
  static const _maxAudioSeconds = 120;

  final _messageController = TextEditingController();
  final _messageFocus = FocusNode();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  final List<ChatAttachment> _attachments = [];
  final List<int> _recordedAudio = [];

  late final StreamSubscription<ChatSendFailure> _sendFailureSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _audioStreamDone;
  Timer? _recordingTimer;
  Uint8List? _voiceDraft;
  int _recordingSeconds = 0;
  bool _isRecording = false;
  bool _isSending = false;
  bool _recordingTooLarge = false;
  bool _recordingStreamFailed = false;
  bool _sendRecordingWhenStopped = false;
  bool _holdReleaseRequested = false;

  @override
  void initState() {
    super.initState();
    _sendFailureSubscription = ChatService.sendFailures.listen((failure) {
      if (!mounted || failure.conversationId != widget.conversationId) return;
      Get.snackbar('error'.tr, '${'chat_send_error'.tr}: ${failure.error}');
    });
  }

  Future<void> _showAttachmentOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF202C33),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF52616B),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _AttachmentOption(
                    icon: Icons.camera_alt_rounded,
                    color: const Color(0xFFE35D83),
                    label: 'chat_camera'.tr,
                    onTap: () => Navigator.pop(context, 'camera'),
                  ),
                  _AttachmentOption(
                    icon: Icons.photo_library_rounded,
                    color: const Color(0xFF8B69D4),
                    label: 'chat_photos'.tr,
                    onTap: () => Navigator.pop(context, 'photos'),
                  ),
                  _AttachmentOption(
                    icon: Icons.insert_drive_file_rounded,
                    color: const Color(0xFF398BD4),
                    label: 'chat_documents'.tr,
                    onTap: () => Navigator.pop(context, 'documents'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'camera':
        await _pickPhoto(ImageSource.camera);
        return;
      case 'photos':
        await _pickPhoto(ImageSource.gallery);
        return;
      case 'documents':
        await _pickAttachments();
        return;
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_attachments.length >= 5) {
      Get.snackbar('error'.tr, 'chat_max_attachments'.tr);
      return;
    }
    try {
      final photo = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (bytes.isEmpty || bytes.length >= 15 * 1024 * 1024) {
        Get.snackbar(
          'error'.tr,
          'chat_file_too_large'.trParams({'name': photo.name}),
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _attachments.add(
          ChatAttachment(
            name: photo.name,
            bytes: bytes,
            contentType: ChatService.contentTypeFor(photo.name),
            kind: 'image',
          ),
        );
      });
    } on PlatformException catch (error, stackTrace) {
      if (source == ImageSource.camera &&
          (error.code == 'no_available_camera' ||
              error.code == 'camera_access_denied')) {
        debugPrint('Chat camera unavailable; opening the photo gallery.');
        if (mounted) {
          Get.snackbar(
            'chat_camera_unavailable_title'.tr,
            'chat_camera_unavailable_fallback'.tr,
          );
        }
        await _pickPhoto(ImageSource.gallery);
        return;
      }
      debugPrint('Could not select chat photo: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar('error'.tr, '${'chat_file_read_error'.tr}: $error');
      }
    } catch (error, stackTrace) {
      debugPrint('Could not select chat photo: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar('error'.tr, '${'chat_file_read_error'.tr}: $error');
      }
    }
  }

  @override
  void dispose() {
    unawaited(_sendFailureSubscription.cancel());
    _recordingTimer?.cancel();
    _audioSubscription?.cancel();
    _recorder.dispose();
    _messageController.dispose();
    _messageFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.any,
      );
      if (result == null || !mounted) return;
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          Get.snackbar('error'.tr, 'chat_file_read_error'.tr);
          continue;
        }
        if (bytes.length >= 15 * 1024 * 1024) {
          Get.snackbar(
            'error'.tr,
            'chat_file_too_large'.trParams({'name': file.name}),
          );
          continue;
        }
        final contentType = ChatService.contentTypeFor(file.name);
        final kind = contentType.startsWith('image/')
            ? 'image'
            : contentType.startsWith('audio/')
            ? 'audio'
            : 'file';
        _attachments.add(
          ChatAttachment(
            name: file.name,
            bytes: bytes,
            contentType: contentType,
            kind: kind,
          ),
        );
      }
      if (_attachments.length > 5) {
        _attachments.removeRange(5, _attachments.length);
        Get.snackbar('error'.tr, 'chat_max_attachments'.tr);
      }
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      debugPrint('Could not pick chat attachments: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted)
        Get.snackbar('error'.tr, '${'chat_file_read_error'.tr}: $error');
    }
  }

  Future<void> _startRecording() async {
    try {
      if (_isRecording || _isSending) return;
      if (!await _recorder.hasPermission()) {
        _sendRecordingWhenStopped = false;
        _holdReleaseRequested = false;
        Get.snackbar('chat_voice_title'.tr, 'chat_microphone_permission'.tr);
        return;
      }
      _recordedAudio.clear();
      _recordingTooLarge = false;
      _recordingStreamFailed = false;
      _recordingSeconds = 0;
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _audioStreamDone = Completer<void>();
      _audioSubscription = stream.listen(
        (bytes) {
          if (_recordingTooLarge) return;
          if (_recordedAudio.length + bytes.length > _maxAudioBytes) {
            _recordingTooLarge = true;
            unawaited(_stopRecording());
            return;
          }
          _recordedAudio.addAll(bytes);
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Voice recording stream failed: $error');
          debugPrintStack(stackTrace: stackTrace);
          _recordingStreamFailed = true;
          if (!(_audioStreamDone?.isCompleted ?? true)) {
            _audioStreamDone!.complete();
          }
        },
        onDone: () {
          if (!(_audioStreamDone?.isCompleted ?? true)) {
            _audioStreamDone!.complete();
          }
        },
      );
      if (!mounted) return;
      setState(() => _isRecording = true);
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= _maxAudioSeconds) {
          unawaited(_stopRecording());
        }
      });
      if (_holdReleaseRequested) unawaited(_stopRecording());
    } catch (error, stackTrace) {
      _sendRecordingWhenStopped = false;
      _holdReleaseRequested = false;
      debugPrint('Could not start voice recording: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) Get.snackbar('error'.tr, '${'chat_voice_error'.tr}: $error');
    }
  }

  void _beginHoldRecording() {
    if (_isSending || _hasSendableContent || _sendRecordingWhenStopped) return;
    _sendRecordingWhenStopped = true;
    _holdReleaseRequested = false;
    unawaited(_startRecording());
  }

  void _releaseHoldRecording() {
    if (!_sendRecordingWhenStopped) return;
    _holdReleaseRequested = true;
    if (_isRecording) unawaited(_stopRecording());
  }

  void _cancelHoldRecording() {
    if (!_sendRecordingWhenStopped) return;
    _holdReleaseRequested = false;
    _sendRecordingWhenStopped = false;
    unawaited(_cancelRecording());
  }

  Future<void> _stopRecording() async {
    if (!_isRecording && _recordingTimer == null) return;
    final sendWhenStopped = _sendRecordingWhenStopped;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      await _recorder.stop();
      try {
        await _audioStreamDone?.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        await _audioSubscription?.cancel();
      }
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _audioStreamDone = null;
      if (_recordingStreamFailed) {
        throw StateError('The audio stream stopped unexpectedly.');
      }
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _voiceDraft = _recordingTooLarge || _recordedAudio.isEmpty
            ? null
            : Uint8List.fromList(_recordedAudio);
      });
      _sendRecordingWhenStopped = false;
      _holdReleaseRequested = false;
      if (_recordingTooLarge) {
        Get.snackbar('error'.tr, 'chat_voice_too_large'.tr);
      } else if (_voiceDraft == null) {
        Get.snackbar('error'.tr, 'chat_voice_empty'.tr);
      } else if (sendWhenStopped) {
        await _sendMessage();
      }
    } catch (error, stackTrace) {
      _sendRecordingWhenStopped = false;
      _holdReleaseRequested = false;
      debugPrint('Could not stop voice recording: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isRecording = false);
        Get.snackbar('error'.tr, '${'chat_voice_error'.tr}: $error');
      }
    }
  }

  Future<void> _cancelRecording() async {
    _sendRecordingWhenStopped = false;
    _holdReleaseRequested = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      await _recorder.cancel();
    } catch (error, stackTrace) {
      debugPrint('Could not cancel voice recording: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    _audioStreamDone = null;
    _recordedAudio.clear();
    if (mounted) setState(() => _isRecording = false);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final attachments = [..._attachments];
    if (_voiceDraft case final voice?) {
      attachments.add(
        ChatAttachment(
          name: 'voice_${DateTime.now().millisecondsSinceEpoch}.wav',
          bytes: _pcm16ToWav(voice),
          contentType: 'audio/wav',
          kind: 'audio',
        ),
      );
    }
    if (text.isEmpty && attachments.isEmpty) return;
    setState(() => _isSending = true);
    try {
      await ChatService.sendMessage(
        conversationId: widget.conversationId,
        text: text,
        attachments: attachments,
      );
      _messageController.clear();
      _attachments.clear();
      _voiceDraft = null;
      if (mounted) setState(() {});
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Could not send chat message: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) Get.snackbar('error'.tr, '${'chat_send_error'.tr}: $error');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    initializeDateFormatting(Get.locale?.toString());
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        backgroundColor: _headerColor,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ChatService.conversationRef(
            widget.conversationId,
          ).snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data() ?? const <String, dynamic>{};
            final group = data['type'] == 'group';
            final names = Map<String, dynamic>.from(
              data['participantNames'] as Map? ?? const {},
            );
            final participants = List<String>.from(
              data['memberUids'] as List? ?? [],
            );
            final ownerViewingPeerChat =
                BusinessAccessService.isOwner.value &&
                !group &&
                !participants.contains(currentUid);
            final otherUid =
                participants.where((uid) => uid != currentUid).firstOrNull ??
                '';
            final title = group
                ? (data['title']?.toString() ?? 'chat_group'.tr)
                : ownerViewingPeerChat
                ? participants
                      .map((uid) => names[uid]?.toString().trim() ?? '')
                      .where((name) => name.isNotEmpty)
                      .join(' · ')
                : names[otherUid]?.toString() ?? 'chat_private'.tr;
            return Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: const Color(0xFF26343D),
                  child: Icon(
                    group ? Icons.groups_rounded : Icons.person_rounded,
                    color: const Color(0xFFB7C7CE),
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        group
                            ? _participantNamesLabel(
                                names,
                                participants.where((uid) => uid != currentUid),
                                maxNames: 3,
                              )
                            : ownerViewingPeerChat
                            ? 'chat_owner_viewing'.tr
                            : 'chat_private_subtitle'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF9EADB5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: Column(
        children: [
          const _ChatOfflineBanner(),
          Expanded(
            child: CustomPaint(
              painter: _ChatWallpaperPainter(),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ChatService.watchMessages(widget.conversationId),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Text(
                          '${'chat_messages_error'.tr}\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFD4DDE1)),
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: _green),
                    );
                  }
                  final messages = snapshot.data!.docs;
                  if (messages.isEmpty) {
                    return Center(
                      child: Container(
                        margin: const EdgeInsets.all(28),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF182229),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'chat_first_message'.tr,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFD1D9DD),
                            height: 1.45,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index].data();
                      return _MessageBubble(
                        data: message,
                        isMine: message['senderUid'] == currentUid,
                        isPending: messages[index].metadata.hasPendingWrites,
                      );
                    },
                  );
                },
              ),
            ),
          ),
          _buildComposerAccess(),
        ],
      ),
    );
  }

  Widget _buildComposerAccess() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ChatService.conversationRef(widget.conversationId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final participants = List<String>.from(
          data?['memberUids'] as List? ?? const [],
        );
        if (BusinessAccessService.isOwner.value &&
            !participants.contains(uid)) {
          return SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              color: _pageColor,
              padding: const EdgeInsets.all(14),
              child: Text(
                'chat_read_only'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFADB4BE), fontSize: 12),
              ),
            ),
          );
        }
        return _buildComposer();
      },
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Container(
        color: _pageColor,
        padding: const EdgeInsets.fromLTRB(7, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isRecording || _voiceDraft != null || _attachments.isNotEmpty)
              _buildDraftTray(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'chat_attach'.tr,
                  onPressed: _isSending || _isRecording
                      ? null
                      : _showAttachmentOptions,
                  icon: const Icon(Icons.add_rounded),
                  color: const Color(0xFFD4DDE1),
                  iconSize: 29,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocus,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 3000,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'chat_message_hint'.tr,
                      counterText: '',
                      filled: true,
                      hintStyle: const TextStyle(
                        color: Color(0xFF8696A0),
                        fontSize: 15,
                      ),
                      fillColor: const Color(0xFF202C33),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: const TextStyle(
                      color: Color(0xFFE9EDEF),
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'chat_camera'.tr,
                  onPressed: _isSending || _isRecording
                      ? null
                      : () => _pickPhoto(ImageSource.camera),
                  color: const Color(0xFFD4DDE1),
                  icon: const Icon(Icons.camera_alt_outlined),
                ),
                const SizedBox(width: 2),
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) {
                    if (!_hasSendableContent) _beginHoldRecording();
                  },
                  onPointerUp: (_) {
                    if (_sendRecordingWhenStopped) {
                      _releaseHoldRecording();
                    } else if (_hasSendableContent && !_isSending) {
                      unawaited(_sendMessage());
                    }
                  },
                  onPointerCancel: (_) => _cancelHoldRecording(),
                  child: Semantics(
                    button: true,
                    label: _isRecording
                        ? 'chat_release_to_send'.tr
                        : _hasSendableContent
                        ? 'chat_send'.tr
                        : 'chat_hold_to_record'.tr,
                    onTap: () {
                      if (_isRecording) {
                        _releaseHoldRecording();
                      } else if (_hasSendableContent) {
                        unawaited(_sendMessage());
                      } else {
                        _beginHoldRecording();
                      }
                    },
                    child: Tooltip(
                      message: _isRecording
                          ? 'chat_release_to_send'.tr
                          : _hasSendableContent
                          ? 'chat_send'.tr
                          : 'chat_hold_to_record'.tr,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _isSending
                              ? const Color(0xFF31574F)
                              : _isRecording
                              ? const Color(0xFFEA4335)
                              : _green,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: _isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                _hasSendableContent
                                    ? Icons.send_rounded
                                    : _isRecording
                                    ? Icons.mic_rounded
                                    : Icons.mic_none_rounded,
                                color: const Color(0xFF071A16),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasSendableContent =>
      _messageController.text.trim().isNotEmpty ||
      _attachments.isNotEmpty ||
      _voiceDraft != null;

  Widget _buildDraftTray() {
    if (_isRecording) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 9),
        child: Row(
          children: [
            const Icon(
              Icons.fiber_manual_record,
              color: Color(0xFFEA4335),
              size: 15,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${'chat_recording'.tr} ${_formatDuration(_recordingSeconds)}',
                style: const TextStyle(
                  color: Color(0xFFE9EDEF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_sendRecordingWhenStopped)
              Text(
                'chat_release_to_send'.tr,
                style: const TextStyle(color: Color(0xFFADB4BE), fontSize: 11),
              ),
            TextButton(
              onPressed: _sendRecordingWhenStopped
                  ? _cancelHoldRecording
                  : _cancelRecording,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEA8A83),
              ),
              child: Text('cancel'.tr),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 9),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (_voiceDraft != null)
            _draftChip(
              icon: Icons.mic_rounded,
              label:
                  '${'chat_voice_draft'.tr} · ${_formatDuration(_recordingSeconds)}',
              onDeleted: () => setState(() => _voiceDraft = null),
            ),
          for (var index = 0; index < _attachments.length; index++)
            _draftChip(
              icon: _attachments[index].kind == 'image'
                  ? Icons.image_outlined
                  : Icons.insert_drive_file_outlined,
              label: _attachments[index].name,
              onDeleted: () => setState(() => _attachments.removeAt(index)),
            ),
        ],
      ),
    );
  }

  Widget _draftChip({
    required IconData icon,
    required String label,
    required VoidCallback onDeleted,
  }) {
    return InputChip(
      avatar: Icon(icon, size: 17, color: const Color(0xFFD4DDE1)),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFFE9EDEF)),
      ),
      onDeleted: onDeleted,
      backgroundColor: const Color(0xFF202C33),
      deleteIconColor: const Color(0xFFB7C7CE),
      side: BorderSide.none,
    );
  }
}

String _participantNamesLabel(
  Map<String, dynamic> participantNames,
  Iterable<String> participantUids, {
  int maxNames = 3,
}) {
  final names = participantUids
      .map((uid) => participantNames[uid]?.toString().trim() ?? '')
      .where((name) => name.isNotEmpty)
      .toList();
  if (names.isEmpty) return 'chat_group'.tr;
  final visibleNames = names.take(maxNames).join(', ');
  final remaining = names.length - maxNames;
  return remaining > 0 ? '$visibleNames +$remaining' : visibleNames;
}

class _AttachmentOption extends StatelessWidget {
  const _AttachmentOption({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 55,
                height: 55,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 25),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFD4DDE1), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatWallpaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF203039).withValues(alpha: .36)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var row = -1; row * 96.0 < size.height + 96; row++) {
      for (var column = -1; column * 96.0 < size.width + 96; column++) {
        final x = column * 96.0 + (row.isEven ? 0 : 44);
        final y = row * 96.0;
        switch ((row - column) % 4) {
          case 0:
            _drawChatIcon(canvas, Offset(x + 24, y + 26), stroke);
            break;
          case 1:
            _drawCoinIcon(canvas, Offset(x + 25, y + 25), stroke);
            break;
          case 2:
            _drawChartIcon(canvas, Offset(x + 25, y + 25), stroke);
            break;
          default:
            _drawBagIcon(canvas, Offset(x + 25, y + 25), stroke);
        }
      }
    }
  }

  void _drawChatIcon(Canvas canvas, Offset center, Paint paint) {
    final rect = Rect.fromCenter(center: center, width: 31, height: 22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      paint,
    );
    final tail = Path()
      ..moveTo(center.dx - 5, center.dy + 11)
      ..lineTo(center.dx - 10, center.dy + 17)
      ..lineTo(center.dx + 1, center.dy + 11);
    canvas.drawPath(tail, paint);
    canvas.drawCircle(Offset(center.dx - 6, center.dy), 1, paint);
    canvas.drawCircle(center, 1, paint);
    canvas.drawCircle(Offset(center.dx + 6, center.dy), 1, paint);
  }

  void _drawCoinIcon(Canvas canvas, Offset center, Paint paint) {
    canvas.drawCircle(center, 14, paint);
    canvas.drawCircle(center, 10, paint);
    canvas.drawLine(
      Offset(center.dx, center.dy - 6),
      Offset(center.dx, center.dy + 6),
      paint,
    );
    canvas.drawArc(
      Rect.fromCenter(center: center, width: 8, height: 5),
      0,
      3.14,
      false,
      paint,
    );
  }

  void _drawChartIcon(Canvas canvas, Offset center, Paint paint) {
    final rect = Rect.fromCenter(center: center, width: 29, height: 25);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      paint,
    );
    final graph = Path()
      ..moveTo(center.dx - 9, center.dy + 5)
      ..lineTo(center.dx - 3, center.dy - 2)
      ..lineTo(center.dx + 2, center.dy + 2)
      ..lineTo(center.dx + 9, center.dy - 7);
    canvas.drawPath(graph, paint);
  }

  void _drawBagIcon(Canvas canvas, Offset center, Paint paint) {
    final rect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + 3),
      width: 25,
      height: 22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      paint,
    );
    final handle = Path()
      ..moveTo(center.dx - 6, center.dy - 6)
      ..quadraticBezierTo(
        center.dx - 6,
        center.dy - 14,
        center.dx,
        center.dy - 14,
      )
      ..quadraticBezierTo(
        center.dx + 6,
        center.dy - 14,
        center.dx + 6,
        center.dy - 6,
      );
    canvas.drawPath(handle, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.data,
    required this.isMine,
    required this.isPending,
  });

  final Map<String, dynamic> data;
  final bool isMine;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final attachments = List<Map<String, dynamic>>.from(
      (data['attachments'] as List? ?? []).map(
        (value) => Map<String, dynamic>.from(value as Map),
      ),
    );
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final bubbleColor = isMine
        ? const Color(0xFF005C4B)
        : const Color(0xFF202C33);
    const textColor = Color(0xFFE9EDEF);
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .80,
        ),
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.fromLTRB(11, 8, 9, 6),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMine ? 12 : 3),
            bottomRight: Radius.circular(isMine ? 3 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                data['senderName']?.toString() ?? 'chat_staff'.tr,
                style: const TextStyle(
                  color: Color(0xFF53BDEB),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            if ((data['text']?.toString() ?? '').trim().isNotEmpty)
              Text(
                data['text'].toString(),
                style: const TextStyle(
                  color: textColor,
                  height: 1.35,
                  fontSize: 15,
                ),
              ),
            for (final attachment in attachments)
              _MessageAttachment(data: attachment, isMine: isMine),
            if (createdAt != null || (isMine && isPending))
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isMine && isPending)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            'chat_message_pending'.tr,
                            style: const TextStyle(
                              color: Color(0xFFB0C0C7),
                              fontSize: 10,
                            ),
                          ),
                        ),
                      if (createdAt != null)
                        Text(
                          DateFormat.Hm().format(createdAt),
                          style: const TextStyle(
                            color: Color(0xFFB0C0C7),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageAttachment extends StatefulWidget {
  const _MessageAttachment({required this.data, required this.isMine});

  final Map<String, dynamic> data;
  final bool isMine;

  @override
  State<_MessageAttachment> createState() => _MessageAttachmentState();
}

class _MessageAttachmentState extends State<_MessageAttachment> {
  late final AudioPlayer _audioPlayer;
  bool _audioReady = false;
  bool _audioError = false;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    if (widget.data['kind'] == 'audio') _loadAudio();
  }

  Future<void> _loadAudio() async {
    try {
      await _audioPlayer.setUrl(widget.data['url'].toString());
      if (mounted) setState(() => _audioReady = true);
    } catch (error, stackTrace) {
      debugPrint('Could not load chat audio: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _audioError = true);
    }
  }

  Future<void> _downloadDocument(String url, String name) async {
    if (url.isEmpty) {
      Get.snackbar('error'.tr, 'chat_file_download_error'.tr);
      return;
    }

    setState(() => _isDownloading = true);
    try {
      final bytes = await FirebaseStorage.instance
          .refFromURL(url)
          .getData(15 * 1024 * 1024);
      if (bytes == null) {
        throw StateError('The downloaded chat document was empty.');
      }
      final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'chat_download'.tr,
        fileName: safeName.isEmpty ? 'chat_attachment'.tr : safeName,
        bytes: bytes,
      );
      if (savedPath == null || !mounted) return;
      Get.snackbar('success'.tr, 'chat_file_downloaded'.tr);
    } catch (error, stackTrace) {
      debugPrint('Could not download chat document: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar('error'.tr, '${'chat_file_download_error'.tr}: $error');
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.data['url']?.toString() ?? '';
    final kind = widget.data['kind']?.toString() ?? 'file';
    final name = widget.data['name']?.toString() ?? 'chat_attachment'.tr;
    const fg = Color(0xFFE9EDEF);
    if (kind == 'image') {
      return Padding(
        padding: const EdgeInsets.only(top: 7),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width * .68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.network(
                  url,
                  width: 220,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _fileCard(name, fg),
                ),
              ),
              const SizedBox(height: 6),
              _downloadButton(url, name),
            ],
          ),
        ),
      );
    }
    if (kind == 'audio') {
      return Padding(
        padding: const EdgeInsets.only(top: 7),
        child: SizedBox(
          width: 235,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.isMine
                      ? const Color(0xFF174C43)
                      : const Color(0xFF2A3942),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: !_audioReady || _audioError
                          ? null
                          : () => _audioPlayer.playing
                                ? _audioPlayer.pause()
                                : _audioPlayer.play(),
                      icon: StreamBuilder<PlayerState>(
                        stream: _audioPlayer.playerStateStream,
                        builder: (context, snapshot) {
                          return Icon(
                            snapshot.data?.playing == true
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                            size: 31,
                            color: fg,
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<Duration?>(
                        stream: _audioPlayer.durationStream,
                        builder: (context, snapshot) {
                          final duration = snapshot.data;
                          return Text(
                            _audioError
                                ? 'chat_audio_unavailable'.tr
                                : !_audioReady
                                ? 'chat_audio_loading'.tr
                                : '${'chat_voice_title'.tr} · ${_formatDuration((duration?.inSeconds ?? 0))}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: fg, fontSize: 12),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              _downloadButton(url, name),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width * .68,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: url.isEmpty
                  ? null
                  : () async {
                      try {
                        final opened = await launchUrl(Uri.parse(url));
                        if (!opened && context.mounted) {
                          Get.snackbar('error'.tr, 'chat_file_open_error'.tr);
                        }
                      } catch (error, stackTrace) {
                        debugPrint('Could not open chat attachment: $error');
                        debugPrintStack(stackTrace: stackTrace);
                        if (context.mounted) {
                          Get.snackbar(
                            'error'.tr,
                            '${'chat_file_open_error'.tr}: $error',
                          );
                        }
                      }
                    },
              borderRadius: BorderRadius.circular(10),
              child: _fileCard(name, fg),
            ),
            const SizedBox(height: 6),
            _downloadButton(url, name),
          ],
        ),
      ),
    );
  }

  Widget _downloadButton(String url, String name) {
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton.filled(
        tooltip: 'chat_download'.tr,
        onPressed: _isDownloading ? null : () => _downloadDocument(url, name),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF2878F0),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF526B91),
          fixedSize: const Size(38, 38),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
        icon: _isDownloading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.download_rounded, size: 19),
      ),
    );
  }

  Widget _fileCard(String name, Color color) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: widget.isMine
            ? const Color(0xFF174C43)
            : const Color(0xFF2A3942),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, color: color, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

Uint8List _pcm16ToWav(Uint8List pcm) {
  final dataLength = pcm.length - (pcm.length % 2);
  if (dataLength == 0) {
    throw StateError('The voice recording is empty.');
  }
  final header = ByteData(44)
    ..setUint8(0, 0x52)
    ..setUint8(1, 0x49)
    ..setUint8(2, 0x46)
    ..setUint8(3, 0x46)
    ..setUint32(4, dataLength + 36, Endian.little)
    ..setUint8(8, 0x57)
    ..setUint8(9, 0x41)
    ..setUint8(10, 0x56)
    ..setUint8(11, 0x45)
    ..setUint8(12, 0x66)
    ..setUint8(13, 0x6d)
    ..setUint8(14, 0x74)
    ..setUint8(15, 0x20)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 16000, Endian.little)
    ..setUint32(28, 32000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint8(36, 0x64)
    ..setUint8(37, 0x61)
    ..setUint8(38, 0x74)
    ..setUint8(39, 0x61)
    ..setUint32(40, dataLength, Endian.little);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...pcm.sublist(0, dataLength),
  ]);
}
