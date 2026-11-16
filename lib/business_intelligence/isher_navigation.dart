import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/subscription_controller.dart';

enum IsherDestination {
  transactions,
  invoices,
  receipts,
  quotation,
  analytics,
  jobs,
  tasks,
  staff,
  pos,
  creativeStudio,
}

extension IsherDestinationInfo on IsherDestination {
  String get route => switch (this) {
    IsherDestination.transactions => AppRoutes.transactions,
    IsherDestination.invoices => AppRoutes.invoicesList,
    IsherDestination.receipts => AppRoutes.receiptsList,
    IsherDestination.quotation => AppRoutes.quotation,
    IsherDestination.analytics => AppRoutes.analytics,
    IsherDestination.jobs => AppRoutes.jobs,
    IsherDestination.tasks => AppRoutes.tasks,
    IsherDestination.staff => AppRoutes.staff,
    IsherDestination.pos => AppRoutes.pos,
    IsherDestination.creativeStudio => AppRoutes.creativeStudio,
  };

  String get label => this == IsherDestination.creativeStudio
      ? (Get.locale?.languageCode == 'sw'
            ? 'Studio ya Ubunifu'
            : 'Creative Studio')
      : 'bi_navigation_$name'.tr;
}

final _navigationPrefix = RegExp(
  r"^\s*(?:(?:tafadhali|naomba|please|isher|isher ai|hey isher|hi isher|sawa|ok|okay)[,\s]+)*(?:(?:unaweza|naweza)\s+(?:kunifungulia|kufungua)|(?:can|could|would)\s+you\s+open|fungua|nifungulie|nifungulia|open|go to)\b",
  caseSensitive: false,
);

bool isIsherNavigationCommand(String text) => _navigationPrefix.hasMatch(text);

IsherDestination? parseIsherNavigationCommand(String text) {
  final match = _navigationPrefix.firstMatch(text);
  if (match == null) return null;
  var target = text.substring(match.end).trim().toLowerCase();
  target = target.replaceFirst(RegExp(r'[.!?]+\s*$'), '').trim();
  target = target.replaceFirst(
    RegExp(r'^(?:the|me|for me|mimi|kwangu)\s+'),
    '',
  );
  target = target.replaceFirst(
    RegExp(
      r'^(?:(?:ukurasa|page|screen)\s+(?:wa|ya|la|za|of)\s+|(?:page|screen|ukurasa)\s+(?:ya\s+)?|(?:orodha|list)\s+(?:ya|of)\s+)',
    ),
    '',
  );
  target = target
      .replaceFirst(
        RegExp(r'\s+(?:tafadhali|please|kwenye app|in the app)$'),
        '',
      )
      .trim();
  return switch (target) {
    'miamala' ||
    'muamala' ||
    'transactions' ||
    'transaction' ||
    'miamala ya biashara' => IsherDestination.transactions,
    'invoice' ||
    'invoices' ||
    'ankara' ||
    'invoice list' ||
    'invoices list' ||
    'ankara za biashara' => IsherDestination.invoices,
    'risiti' ||
    'receipt' ||
    'receipts' ||
    'receipts list' => IsherDestination.receipts,
    'quotation' ||
    'quotations' ||
    'quote' ||
    'nukuu' => IsherDestination.quotation,
    'ripoti' ||
    'report' ||
    'reports' ||
    'analytics' => IsherDestination.analytics,
    'jobs' || 'job' || 'kazi za wateja' => IsherDestination.jobs,
    'tasks' || 'task' || 'kazi' => IsherDestination.tasks,
    'wafanyakazi' || 'staff' || 'employees' => IsherDestination.staff,
    'pos' => IsherDestination.pos,
    'creative studio' ||
    'poster studio' ||
    'creative design' ||
    'studio ya ubunifu' ||
    'studio ya poster' ||
    'kutengeneza poster' ||
    'kutengeneza mabango' => IsherDestination.creativeStudio,
    _ => null,
  };
}

Future<bool> openIsherDestination({
  required BuildContext context,
  required IsherDestination destination,
  required String businessId,
  required bool Function() isCurrent,
  Future<void> Function()? beforeOpen,
  Future<void> Function()? afterReturn,
}) => _openAuthorizedIsherRoute(
  context: context,
  route: destination.route,
  businessId: businessId,
  isCurrent: isCurrent,
  receiptRestricted: destination == IsherDestination.receipts,
  arguments: destination == IsherDestination.transactions
      ? {'shopNickname': BusinessAccessService.shopNickname.value}
      : null,
  beforeOpen: beforeOpen,
  afterReturn: afterReturn,
);

Future<bool> openIsherAssistant({
  required BuildContext context,
  required String businessId,
  required bool Function() isCurrent,
  required bool voice,
}) => _openAuthorizedIsherRoute(
  context: context,
  route: AppRoutes.businessIntelligence,
  businessId: businessId,
  isCurrent: isCurrent,
  arguments: voice ? 'voice' : 'chat',
);

Future<bool> _openAuthorizedIsherRoute({
  required BuildContext context,
  required String route,
  required String businessId,
  required bool Function() isCurrent,
  bool receiptRestricted = false,
  Object? arguments,
  Future<void> Function()? beforeOpen,
  Future<void> Function()? afterReturn,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  bool allowed() =>
      context.mounted &&
      uid != null &&
      FirebaseAuth.instance.currentUser?.uid == uid &&
      isCurrent() &&
      BusinessAccessService.hasBusinessAccess &&
      BusinessAccessService.businessUid.value == businessId &&
      BusinessAccessService.canAccessRoute(route);
  void notice(String key) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(key.tr)));
    }
  }

  if (!allowed()) {
    notice('staff_no_permission');
    return false;
  }
  try {
    var role = '';
    if (BusinessAccessService.isOwner.value) {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(businessId)
          .collection('profile')
          .doc('company')
          .get();
      role = (profile.data()?['role']?.toString() ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
    }
    if (!allowed()) {
      notice('staff_no_permission');
      return false;
    }
    if (receiptRestricted && role != 'superadmin') {
      notice('staff_no_permission');
      return false;
    }
    if (role != 'admin' && role != 'superadmin') {
      final controller = Get.isRegistered<SubscriptionController>()
          ? Get.find<SubscriptionController>()
          : SubscriptionController();
      final status = await controller.getBusinessSubscriptionStatus();
      if (!allowed()) {
        notice('staff_no_permission');
        return false;
      }
      if (!status.isSubscribed && !status.isTrial) {
        notice('subscription_required_message');
        return false;
      }
    }
    if (beforeOpen != null) await beforeOpen();
    if (!allowed()) {
      notice('staff_no_permission');
      return false;
    }
    final navigation = Get.toNamed(route, arguments: arguments);
    if (navigation == null) throw StateError('Navigation unavailable');
    unawaited(
      navigation
          .then<void>((_) async {
            if (afterReturn != null && allowed()) await afterReturn();
          })
          .catchError((Object error, StackTrace stack) {
            debugPrint('Isher navigation return failed: ${error.runtimeType}');
            debugPrintStack(stackTrace: stack);
            notice('bi_navigation_error');
          }),
    );
    return true;
  } catch (error, stack) {
    debugPrint('Isher navigation failed: ${error.runtimeType}');
    debugPrintStack(stackTrace: stack);
    notice('bi_navigation_error');
    return false;
  }
}
