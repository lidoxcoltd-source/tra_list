import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/staff_service.dart';
import 'package:uuid/uuid.dart';

class ChatSendFailure {
  const ChatSendFailure({required this.conversationId, required this.error});

  final String conversationId;
  final Object error;
}

class ChatAttachment {
  const ChatAttachment({
    required this.name,
    required this.bytes,
    required this.contentType,
    required this.kind,
  });

  final String name;
  final Uint8List bytes;
  final String contentType;
  final String kind;
}

class ChatService {
  ChatService._();

  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;
  static final _sendFailures = StreamController<ChatSendFailure>.broadcast();
  static const _uuid = Uuid();

  static Stream<ChatSendFailure> get sendFailures => _sendFailures.stream;

  static String get _businessId => BusinessAccessService.businessId;

  static String get _currentUid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to use business chat.');
    return uid;
  }

  static CollectionReference<Map<String, dynamic>> get _conversations =>
      _db.collection('users').doc(_businessId).collection('chats');

  static DocumentReference<Map<String, dynamic>> get _chatReadRef => _db
      .collection('chatReads')
      .doc(_businessId)
      .collection('members')
      .doc(_currentUid);

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchConversations() {
    final conversations = _conversations.orderBy('updatedAt', descending: true);
    if (BusinessAccessService.isOwner.value) {
      return conversations.snapshots(includeMetadataChanges: true);
    }
    return conversations
        .where('memberUids', arrayContains: _currentUid)
        .limit(100)
        .snapshots(includeMetadataChanges: true);
  }

  static Stream<int> watchUnreadMessageCount() {
    final controller = StreamController<int>();
    final uid = _currentUid;
    QuerySnapshot<Map<String, dynamic>>? conversations;
    DateTime? lastViewedAt;
    var readLoaded = false;
    var conversationsLoaded = false;
    var generation = 0;

    Future<void> emitCount() async {
      if (!readLoaded || !conversationsLoaded || controller.isClosed) return;
      final currentGeneration = ++generation;
      final viewedAt = lastViewedAt;
      final inbound = conversations!.docs.where((conversation) {
        final data = conversation.data();
        if (viewedAt == null) return data['lastSenderUid'] != uid;
        final updatedAt = data['updatedAt'];
        return updatedAt is Timestamp && updatedAt.toDate().isAfter(viewedAt);
      });

      try {
        var count = 0;
        for (final conversation in inbound) {
          if (viewedAt == null) {
            count++;
            continue;
          }
          final messages = await conversation.reference
              .collection('messages')
              .where('createdAt', isGreaterThan: Timestamp.fromDate(viewedAt))
              .get();
          count += messages.docs
              .where((message) => message.data()['senderUid'] != uid)
              .length;
        }
        if (!controller.isClosed && currentGeneration == generation) {
          controller.add(count);
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed && currentGeneration == generation) {
          controller.addError(error, stackTrace);
        }
      }
    }

    final readSubscription = _chatReadRef.snapshots().listen((snapshot) {
      final value = snapshot.data()?['lastViewedAt'];
      lastViewedAt = value is Timestamp ? value.toDate() : null;
      readLoaded = true;
      unawaited(emitCount());
    }, onError: controller.addError);
    final conversationsSubscription = watchConversations().listen((snapshot) {
      conversations = snapshot;
      conversationsLoaded = true;
      unawaited(emitCount());
    }, onError: controller.addError);
    controller.onCancel = () async {
      generation++;
      await readSubscription.cancel();
      await conversationsSubscription.cancel();
    };
    return controller.stream;
  }

  static Future<void> markChatsViewed() async {
    await _chatReadRef.set({'lastViewedAt': FieldValue.serverTimestamp()});
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchPresence() {
    return _db
        .collection('chatPresence')
        .doc(_businessId)
        .collection('members')
        .snapshots();
  }

  static Future<List<StaffMember>> fetchChatStaff() async {
    final response = await FirebaseFunctions.instance
        .httpsCallable('getBusinessChatStaff')
        .call<Map<String, dynamic>>({'businessUid': _businessId});
    final staff = response.data['staff'];
    if (staff is! List) {
      throw StateError('The staff directory response was invalid.');
    }
    return staff
        .map((entry) {
          final data = Map<String, dynamic>.from(entry as Map);
          return StaffMember(
            id: data['uid'].toString(),
            data: {'name': data['name']?.toString() ?? '', 'active': true},
            isLegacy: data['isLegacy'] == true,
          );
        })
        .where((member) => member.id != _currentUid)
        .toList();
  }

  static DocumentReference<Map<String, dynamic>> conversationRef(String id) =>
      _conversations.doc(id);

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(
    String conversationId,
  ) {
    return conversationRef(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots(includeMetadataChanges: true);
  }

  static Future<String> getOrCreateDirectChat({
    required String otherUid,
    required String otherName,
  }) async {
    final currentUid = _currentUid;
    if (otherUid.isEmpty || otherUid == currentUid) {
      throw ArgumentError.value(otherUid, 'otherUid', 'Invalid chat member.');
    }
    final memberSources = <String, String>{};
    if (BusinessAccessService.isOwner.value) {
      final staff = (await StaffService.fetchStaff())
          .where((member) => member.id == otherUid)
          .firstOrNull;
      if (staff == null || staff.data['active'] != true) {
        throw StateError('This staff account is not active.');
      }
      memberSources[currentUid] = 'owner';
      memberSources[otherUid] = staff.isLegacy ? 'legacy' : 'modern';
    } else if (otherUid == BusinessAccessService.businessId) {
      memberSources[currentUid] = BusinessAccessService.isLegacyMembership.value
          ? 'legacy'
          : 'modern';
      memberSources[otherUid] = 'owner';
    } else {
      final staff = (await fetchChatStaff())
          .where((member) => member.id == otherUid)
          .firstOrNull;
      if (staff == null || staff.data['active'] != true) {
        throw StateError('This staff account is not active.');
      }
      memberSources[currentUid] = BusinessAccessService.isLegacyMembership.value
          ? 'legacy'
          : 'modern';
      memberSources[otherUid] = staff.isLegacy ? 'legacy' : 'modern';
    }

    final memberUids = [currentUid, otherUid]..sort();
    final id = 'direct_${memberUids.join('__')}';
    final ref = conversationRef(id);
    final currentUser = FirebaseAuth.instance.currentUser!;
    final currentName = (currentUser.displayName ?? '').trim().isNotEmpty
        ? currentUser.displayName!.trim()
        : (BusinessAccessService.isOwner.value
              ? BusinessAccessService.businessName.value
              : 'Staff');
    final participantNames = <String, String>{
      currentUid: currentName,
      otherUid: otherName.trim().isNotEmpty ? otherName.trim() : 'Staff',
    };

    await _db.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (existing.exists) return;
      final now = FieldValue.serverTimestamp();
      transaction.set(ref, {
        'type': 'direct',
        'title': '',
        'memberUids': memberUids,
        'memberSources': memberSources,
        'participantNames': participantNames,
        'createdBy': currentUid,
        'createdAt': now,
        'updatedAt': now,
        'lastMessage': '',
        'lastSenderUid': '',
      });
    });
    return id;
  }

  static Future<String> getOrCreateBusinessGroup() async {
    if (!BusinessAccessService.isOwner.value) {
      throw StateError('Only the business owner can create the staff group.');
    }
    final ownerUid = _currentUid;
    final members = await StaffService.fetchStaff();
    final activeStaff = members
        .where((member) => member.data['active'] == true)
        .toList();
    final memberUids = <String>{ownerUid};
    final memberSources = <String, String>{ownerUid: 'owner'};
    final participantNames = <String, String>{
      ownerUid: BusinessAccessService.businessName.value.isEmpty
          ? 'Owner'
          : BusinessAccessService.businessName.value,
    };
    for (final member in activeStaff) {
      memberUids.add(member.id);
      memberSources[member.id] = member.isLegacy ? 'legacy' : 'modern';
      participantNames[member.id] =
          member.data['name']?.toString().trim().isNotEmpty == true
          ? member.data['name'].toString().trim()
          : 'Staff';
    }

    const id = 'business_staff_group';
    final ref = conversationRef(id);
    final existing = await ref.get();
    if (existing.exists) {
      await ref.update({
        'memberUids': memberUids.toList(),
        'memberSources': memberSources,
        'participantNames': participantNames,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.set({
        'type': 'group',
        'title': 'Business team',
        'memberUids': memberUids.toList(),
        'memberSources': memberSources,
        'participantNames': participantNames,
        'createdBy': ownerUid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastSenderUid': '',
      });
    }
    return id;
  }

  static Future<void> sendMessage({
    required String conversationId,
    required String text,
    required List<ChatAttachment> attachments,
  }) async {
    final body = text.trim();
    if (body.isEmpty && attachments.isEmpty) return;
    if (body.length > 3000) {
      throw ArgumentError('Chat messages cannot exceed 3,000 characters.');
    }
    if (attachments.length > 5) {
      throw ArgumentError('Send no more than five attachments at once.');
    }

    final uid = _currentUid;
    final user = FirebaseAuth.instance.currentUser!;
    final conversation = conversationRef(conversationId);
    final files = <Map<String, dynamic>>[];
    for (final attachment in attachments) {
      if (attachment.bytes.isEmpty ||
          attachment.bytes.length >= 15 * 1024 * 1024) {
        throw ArgumentError('Each attachment must be smaller than 15 MB.');
      }
      final normalizedName = attachment.name
          .split(RegExp(r'[/\\]'))
          .last
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final safeName = normalizedName.length > 120
          ? normalizedName.substring(normalizedName.length - 120)
          : normalizedName;
      final fileId = _uuid.v4();
      final storagePath =
          'chatAttachments/$_businessId/$conversationId/$fileId-$safeName';
      final reference = _storage.ref(storagePath);
      final upload = await reference.putData(
        attachment.bytes,
        SettableMetadata(contentType: attachment.contentType),
      );
      final url = await upload.ref.getDownloadURL();
      files.add({
        'name': safeName,
        'url': url,
        'storagePath': storagePath,
        'contentType': attachment.contentType,
        'kind': attachment.kind,
        'size': attachment.bytes.length,
      });
    }

    final senderName = (user.displayName ?? '').trim().isNotEmpty
        ? user.displayName!.trim()
        : (BusinessAccessService.isOwner.value
              ? BusinessAccessService.businessName.value
              : 'Staff');
    final batch = _db.batch();
    batch.set(conversation.collection('messages').doc(), {
      'senderUid': uid,
      'senderName': senderName,
      'text': body,
      'attachments': files,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(conversation, {
      'lastMessage': body.isNotEmpty
          ? body
          : files.length == 1
          ? files.first['kind'] == 'audio'
                ? 'Voice message'
                : files.first['name']
          : '${files.length} attachments',
      'lastSenderUid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    unawaited(
      batch.commit().then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Could not sync chat message: $error');
          debugPrintStack(stackTrace: stackTrace);
          _sendFailures.add(
            ChatSendFailure(conversationId: conversationId, error: error),
          );
        },
      ),
    );
  }

  static String contentTypeFor(String filename) {
    final extension = filename.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'wav' => 'audio/wav',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'ogg' || 'opus' => 'audio/ogg',
      'webm' => 'audio/webm',
      _ => 'application/octet-stream',
    };
  }
}
