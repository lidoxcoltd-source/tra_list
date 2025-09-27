import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tra_list/HomePage.dart';
import 'package:tra_list/AddReceiptPage.dart';
import 'package:tra_list/ReceiptsListPageHybrid.dart';
import 'package:tra_list/ReceiptPage.dart';
import 'package:tra_list/FirebaseTestPage.dart';
import 'package:tra_list/ReceiptViewPage.dart';
import 'package:tra_list/RouteTestPage.dart';
import 'package:tra_list/LoginPage.dart';

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

  // Helper method to generate receipt URL
  static String getReceiptRoute(String receiptId) => '/receipt/$receiptId';

  static List<GetPage> routes = [
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
      middlewares: [AuthMiddleware()],
      transition: Transition.rightToLeft,
    ),
  ];
}
