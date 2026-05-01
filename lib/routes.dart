import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tra_list/HomePage.dart';
import 'package:tra_list/AddReceiptPage.dart';
import 'package:tra_list/ReceiptsListPage.dart';
import 'package:tra_list/invoice/categories_page.dart';
import 'package:tra_list/invoice/analytics_page.dart';
import 'package:tra_list/jobs/views/jobs_page.dart';
import 'package:tra_list/subscription_page.dart';

import 'package:tra_list/ReceiptsListPageHybrid.dart';
import 'package:tra_list/ReceiptPage.dart';
import 'package:tra_list/FirebaseTestPage.dart';
import 'package:tra_list/ReceiptViewPage.dart';
import 'package:tra_list/RouteTestPage.dart';
import 'package:tra_list/LoginPage.dart';
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

class AppRoutes {
  static const String login = '/login';
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
  static const String analytics = '/analytics';
  static const String jobs = '/jobs';
  static const String quotation = '/quotation';
  static const String clientCredit = '/client-credit';
  static const String subscription = '/subscription';

  // Helper method to generate receipt URL
  static String getReceiptRoute(String receiptId) => '/receipt/$receiptId';

  static final pages = <GetPage>[
    GetPage(name: login, page: () => LoginPage()),
    GetPage(
      name: home,
      page: () => const HomePage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: addReceipt,
      page: () => const AddReceiptPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: receiptsList,
      page: () => const ReceiptsListPage(),
      middlewares: [AuthMiddleware()],
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
    GetPage(name: invoice, page: () => const InvoicePage()),
    GetPage(name: invoicesList, page: () => const InvoicesPage()),
    GetPage(
      name: transactions,
      page: () => const TransactionsPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: categories,
      page: () => const CategoriesPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: analytics,
      page: () => const AnalyticsPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: jobs,
      page: () => const JobsPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: quotation,
      page: () => const QuotationPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: subscription,
      page: () => const SubscriptionPage(),
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
  ];
}
