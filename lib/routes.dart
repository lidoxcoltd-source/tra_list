import 'package:get/get.dart';
import 'package:tra_list/HomePage.dart';
import 'package:tra_list/AddReceiptPage.dart';
import 'package:tra_list/ReceiptsListPageHybrid.dart';
import 'package:tra_list/ReceiptPage.dart';
import 'package:tra_list/FirebaseTestPage.dart';
import 'package:tra_list/ReceiptViewPage.dart';
import 'package:tra_list/RouteTestPage.dart';

class AppRoutes {
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
    GetPage(
      name: home,
      page: () => const HomePage(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: addReceipt,
      page: () => const AddReceiptPage(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: receiptsList,
      page: () => const ReceiptsListPage(),
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
      transition: Transition.rightToLeft,
    ),
  ];
}
