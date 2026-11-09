import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/isher_packages_page.dart';

void showIsherPackageQuotaNotice(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('isher_package_exhausted_notice'.tr),
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'isher_add_balance'.tr,
          onPressed: () => Get.to(() => const IsherPackagesPage()),
        ),
      ),
    );
}
