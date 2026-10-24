import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tra_list/HomePage.dart';
import 'package:tra_list/AddReceiptPage.dart';
import 'package:tra_list/ReceiptsListPage.dart';
import 'package:tra_list/invoice/categories_page.dart';
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
import 'package:tra_list/services/support_faq_page.dart';
import 'package:tra_list/services/analytics_advice_admin_page.dart';

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
    if (!BusinessAccessService.isReady.value ||
        !BusinessAccessService.isOwner.value) {
      Get.snackbar('error'.tr, 'staff_no_permission'.tr);
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
  static const String addReceipt = '/add-receipt';
  static const String receiptsList = '/receipts';
  static const String sampleReceipt = '/sample-receipt';
  static const String firebaseTest = '/firebase-test';
  static const String routeTest = '/route-test';
  static const String viewReceipt = '/receipt/:id';
  static const String invoice = '/invoice';
  static const String invoicesList = '/invoices';
  static const String transactions = '/transactions';
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
  static const String support = '/support';
  static const String adminSupport = '/admin-support';
  static const String adminAnalyticsAdvice = '/admin-analytics-advice';

  // Helper method to generate receipt URL
  static String getReceiptRoute(String receiptId) => '/receipt/$receiptId';

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
      name: transactions,
      page: () => const TransactionsPage(),
      middlewares: [AuthMiddleware(), BusinessPermissionMiddleware()],
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
      name: adminAnalyticsAdvice,
      page: () => const AnalyticsAdviceAdminPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
  ];
}
