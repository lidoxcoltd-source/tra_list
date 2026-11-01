import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tra_list/HomePage.dart';
import 'package:tra_list/AddReceiptPage.dart';
import 'package:tra_list/ReceiptsListPage.dart';
import 'package:tra_list/invoice/categories_page.dart';
import 'package:tra_list/invoice/add_transaction_page.dart';
import 'package:tra_list/stock/stock_dashboard_page.dart';
import 'package:tra_list/stock/pos_page.dart';
import 'package:tra_list/invoice/analytics_page.dart';
import 'package:tra_list/jobs/views/jobs_page.dart';
import 'package:tra_list/jobs/views/archived_jobs_page.dart';
import 'package:tra_list/subscription_page.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/staff_management_page.dart';
import 'package:tra_list/tasks/tasks_page.dart';
import 'package:tra_list/services/super_admin_subscriptions_page.dart';
import 'package:tra_list/services/app_version_management_page.dart';
import 'package:tra_list/services/downloads_page.dart';
import 'package:tra_list/services/admin_analytics_page.dart';
import 'package:tra_list/services/admin_announcements_page.dart';
import 'package:tra_list/services/super_admin_hub_page.dart';
import 'package:tra_list/services/notifications_page.dart';
import 'package:tra_list/services/download_center_management_page.dart';
import 'package:tra_list/services/support_center_admin_page.dart';
import 'package:tra_list/services/legal_admin_page.dart';
import 'package:tra_list/services/chat_page.dart';
import 'package:tra_list/legal/legal_page.dart';
import 'package:tra_list/legal/legal_service.dart';
import 'package:tra_list/services/support_faq_page.dart';
import 'package:tra_list/services/analytics_advice_admin_page.dart';
import 'package:tra_list/services/account_mode_service.dart';
import 'package:tra_list/services/business_setup_page.dart';
import 'package:tra_list/services/personal_settings_page.dart';
import 'package:tra_list/services/app_urls_page.dart';
import 'package:tra_list/market/market_home_page.dart';
import 'package:tra_list/market/market_post_page.dart';
import 'package:tra_list/market/market_profile_page.dart';
import 'package:tra_list/market/market_business_verification_page.dart';
import 'package:tra_list/market/admin_market_sounds_page.dart';
import 'package:tra_list/market/admin_market_reports_page.dart';

import 'package:tra_list/ReceiptPage.dart';
import 'package:tra_list/FirebaseTestPage.dart';
import 'package:tra_list/ReceiptViewPage.dart';
import 'package:tra_list/RouteTestPage.dart';
import 'package:tra_list/LoginPage.dart';
import 'package:tra_list/splash_page.dart';
import 'package:tra_list/CreateAccountPage.dart';
import 'invoice/InvoicePage.dart';
import 'invoice/InvoicesPage.dart';
import 'invoice/transactions_page.dart';
import 'invoice/quotation_page.dart';
import 'package:tra_list/invoice/document_shares_page.dart';
import 'package:tra_list/invoice/shared_document_page.dart';

class AuthMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    final user = FirebaseAuth.instance.currentUser;

    // If user is not logged in and trying to access protected routes
    if (user == null && route != AppRoutes.login) {
      return const RouteSettings(name: AppRoutes.login);
    }

    // If user is logged in and trying to access login page, redirect to home
    if (user != null && route == AppRoutes.login) {
      return const RouteSettings(name: AppRoutes.home);
    }

    return null;
  }
}

class BusinessPermissionMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    if (AccountModeService.current != AccountMode.business) {
      Get.snackbar('error'.tr, 'mode_business_required'.tr);
      return const RouteSettings(name: AppRoutes.home);
    }
    if (!BusinessAccessService.isReady.value) {
      return const RouteSettings(name: AppRoutes.home);
    }
    if (!BusinessAccessService.canAccessRoute(route ?? '')) {
      Get.snackbar('error'.tr, 'staff_no_permission'.tr);
      return const RouteSettings(name: AppRoutes.home);
    }
    return null;
  }
}

class BusinessOwnerMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    if (AccountModeService.current != AccountMode.business ||
        !BusinessAccessService.isReady.value ||
        !BusinessAccessService.isOwner.value) {
      Get.snackbar('error'.tr, 'staff_no_permission'.tr);
      return const RouteSettings(name: AppRoutes.home);
    }
    return null;
  }
}

class BusinessChatMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    if (AccountModeService.current != AccountMode.business ||
        !BusinessAccessService.isReady.value ||
        !BusinessAccessService.hasBusinessAccess) {
      Get.snackbar('error'.tr, 'chat_business_required'.tr);
      return const RouteSettings(name: AppRoutes.home);
    }
    return null;
  }
}

class PersonalModeMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    if (AccountModeService.current != AccountMode.personal) {
      return const RouteSettings(name: AppRoutes.home);
    }
    return null;
  }
}

class BusinessSetupModeMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    if (AccountModeService.current != AccountMode.business) {
      return const RouteSettings(name: AppRoutes.home);
    }
    return null;
  }
}

class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/';
  static const String homeSection = '/home/:section';
  static const String addReceipt = '/add-receipt';
  static const String receiptsList = '/receipts';
  static const String sampleReceipt = '/sample-receipt';
  static const String firebaseTest = '/firebase-test';
  static const String routeTest = '/route-test';
  static const String viewReceipt = '/receipt/:id';
  static const String invoice = '/invoice';
  static const String invoicesList = '/invoices';
  static const String documentShares = '/document-shares';
  static const String sharedDocument = '/shared-document/:token';
  static const String transactions = '/transactions';
  static const String addTransaction = '/AddTransactionPage';
  static const String chat = '/chat';
  static const String chatRoom = '/chat/:id';
  static const String categories = '/categories';
  static const String stock = '/stock';
  static const String pos = '/pos';
  static const String analytics = '/analytics';
  static const String jobs = '/jobs';
  static const String jobsArchive = '/jobs-archive';
  static const String quotation = '/quotation';
  static const String clientCredit = '/client-credit';
  static const String subscription = '/subscription';
  static const String staff = '/staff';
  static const String tasks = '/tasks';
  static const String adminSubscriptions = '/admin-subscriptions';
  static const String adminAppVersions = '/admin-app-versions';
  static const String downloads = '/downloads';
  static const String adminDownloads = '/admin-downloads';
  static const String adminAnalytics = '/admin-analytics';
  static const String notifications = '/notifications';
  static const String adminAnnouncements = '/admin-announcements';
  static const String adminHub = '/admin-hub';
  static const String adminMarketVerification = '/admin-market-verification';
  static const String adminMarketSounds = '/admin-market-sounds';
  static const String adminMarketReports = '/admin-market-reports';
  static const String support = '/support';
  static const String adminSupport = '/admin-support';
  static const String privacy = '/privacy';
  static const String terms = '/terms';
  static const String adminLegal = '/admin-legal';
  static const String adminAnalyticsAdvice = '/admin-analytics-advice';
  static const String businessSetup = '/business-setup';
  static const String personalSettings = '/personal-settings';
  static const String appUrls = '/app-urls';
  static const String market = '/market';
  static const String marketProfile = '/market/profile/:uid';
  static const String marketPost = '/market/post/:id';

  // Helper method to generate receipt URL
  static String getReceiptRoute(String receiptId) => '/receipt/$receiptId';
  static String getChatRoomRoute(String conversationId) =>
      '/chat/$conversationId';
  static String getHomeSectionRoute(String section) => '/home/$section';

  static String? pendingWebRoute;

  static String? takePendingWebRoute() {
    final route = pendingWebRoute;
    pendingWebRoute = null;
    return route;
  }

  static String? resolveWebLocation(Uri uri) {
    final location = uri.fragment.startsWith('/')
        ? uri.fragment
        : '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
    final parsedLocation = Uri.tryParse(location);
    if (parsedLocation == null) return null;

    final path = parsedLocation.path.replaceFirst(RegExp(r'/+$'), '');
    final normalizedPath = path.isEmpty ? '/' : path;
    for (final page in pages) {
      if (!_matchesRoute(page.name, normalizedPath)) continue;
      if (page.name == homeSection &&
          !const {
            'explore',
            'reports',
            'chat',
          }.contains(normalizedPath.split('/').last)) {
        return null;
      }
      final resolvedPath = page.name.contains('/:')
          ? normalizedPath
          : page.name;
      return parsedLocation.hasQuery
          ? '$resolvedPath?${parsedLocation.query}'
          : resolvedPath;
    }
    return null;
  }

  static bool webRouteRequiresAuthentication(String route) {
    final routePath = Uri.tryParse(route)?.path;
    if (routePath == null) return false;
    for (final page in pages) {
      if (_matchesRoute(page.name, routePath)) {
        return page.middlewares?.any(
              (middleware) => middleware is AuthMiddleware,
            ) ??
            false;
      }
    }
    return false;
  }

  static bool _matchesRoute(String template, String path) {
    final templateSegments = template.split('/');
    final pathSegments = path.split('/');
    if (templateSegments.length != pathSegments.length) return false;
    for (var index = 0; index < templateSegments.length; index++) {
      final templateSegment = templateSegments[index];
      if (templateSegment.startsWith(':')) {
        if (pathSegments[index].isEmpty) return false;
      } else if (templateSegment.toLowerCase() !=
          pathSegments[index].toLowerCase()) {
        return false;
      }
    }
    return true;
  }

  static final pages = <GetPage>[
    GetPage(
      name: splash,
      page: () => const SplashPage(),
      transition: Transition.fadeIn,
    ),
    GetPage(name: login, page: () => LoginPage()),
    GetPage(name: register, page: () => const CreateAccountPage()),
    GetPage(
      name: home,
      page: () => const HomePage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: homeSection,
      page: () => HomePage(initialSection: Get.parameters['section']),
      middlewares: [AuthMiddleware()],
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: businessSetup,
      page: () => const BusinessSetupPage(),
      middlewares: [AuthMiddleware(), BusinessSetupModeMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: market,
      page: () => const MarketHomePage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: marketPost,
      page: () => MarketPostPage(postId: Get.parameters['id'] ?? ''),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: marketProfile,
      page: () => MarketProfilePage(uid: Get.parameters['uid'] ?? ''),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: personalSettings,
      page: () => const PersonalSettingsPage(),
      middlewares: [AuthMiddleware(), PersonalModeMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: appUrls,
      page: () => const AppUrlsPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: addReceipt,
      page: () => const AddReceiptPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: receiptsList,
      page: () => const ReceiptsListPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: sampleReceipt,
      page: () => const ReceiptPage(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: firebaseTest,
      page: () => const FirebaseTestPage(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: routeTest,
      page: () => const RouteTestPage(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: viewReceipt,
      page: () => ReceiptViewPage(),
      // Public route: no AuthMiddleware
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: sharedDocument,
      page: () => SharedDocumentPage(token: Get.parameters['token'] ?? ''),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: invoice,
      page: () => const InvoicePage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
    ),
    GetPage(
      name: invoicesList,
      page: () => const InvoicesPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
    ),
    GetPage(
      name: documentShares,
      page: () =>
          DocumentSharesPage(businessUid: BusinessAccessService.businessId),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
    ),
    GetPage(
      name: transactions,
      page: () => const TransactionsPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: addTransaction,
      page: () => const AddTransactionPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: chat,
      page: () => const ChatPage(),
      middlewares: [AuthMiddleware(), BusinessChatMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: chatRoom,
      page: () => ChatRoomPage(conversationId: Get.parameters['id'] ?? ''),
      middlewares: [AuthMiddleware(), BusinessChatMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: categories,
      page: () => const CategoriesPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: stock,
      page: () => const StockDashboardPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: pos,
      page: () => const PosPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: analytics,
      page: () => const AnalyticsPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: jobs,
      page: () => const JobsPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: jobsArchive,
      page: () => const ArchivedJobsPage(),
      middlewares: [AuthMiddleware(), BusinessOwnerMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: quotation,
      page: () => const QuotationPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: subscription,
      page: () => const SubscriptionPage(),
      middlewares: [AuthMiddleware(), BusinessOwnerMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: staff,
      page: () => const StaffManagementPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
    ),
    GetPage(
      name: tasks,
      page: () => const TasksPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: adminSubscriptions,
      page: () => const SuperAdminSubscriptionsPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: adminAppVersions,
      page: () => const AppVersionManagementPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: downloads,
      page: () => const DownloadsPage(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: adminDownloads,
      page: () => const DownloadCenterManagementPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: adminAnalytics,
      page: () => const AdminAnalyticsPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: notifications,
      page: () => const NotificationsPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: adminAnnouncements,
      page: () => const AdminAnnouncementsPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: adminHub,
      page: () => const SuperAdminHubPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: adminMarketVerification,
      page: () => const MarketBusinessVerificationPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: adminMarketReports,
      page: () => const AdminMarketReportsPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: adminMarketSounds,
      page: () => const AdminMarketSoundsPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: support,
      page: () => const SupportFaqPage(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: adminSupport,
      page: () => const SupportCenterAdminPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: privacy,
      page: () => const LegalPage(kind: LegalKind.privacy),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: terms,
      page: () => const LegalPage(kind: LegalKind.terms),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: adminLegal,
      page: () => const LegalAdminPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: adminAnalyticsAdvice,
      page: () => const AnalyticsAdviceAdminPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
  ];
}
