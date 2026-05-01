// Centralized configuration for all external URLs, emails, and contact information
import 'package:get/get.dart';
// import 'package:mbokashopping/controllers/contact_config_controller.dart';

class AppConfig {
  // Expose contact controller for refresh
  // static ContactConfigController? get contactConfigController =>
  //     _tryGetContactController();

  // Admin toggle for payment feature (dynamic)
  // static bool get paymentEnabled =>
  //     _tryGetContactController()?.paymentEnabled.value ?? true;

  // Safely get the controller instance, relying on InitialBinding.
  // static ContactConfigController? _tryGetContactController() {
  //   if (Get.isRegistered<ContactConfigController>()) {
  //     return Get.find<ContactConfigController>();
  //   }
  //   return null;
  // }

  // API Endpoints (now dynamic from Firebase)
  static String get paymentApiBaseUrl =>
      'https://us-central1-mbokashopping.cloudfunctions.net';
  static String get paymentCompleteEndpoint =>
      'https://us-central1-mbokashopping.cloudfunctions.net/selcomPaymentProxy';

  // App URLs (now dynamic from Firebase)
  static String get appBaseUrl =>
      // _tryGetContactController()?.appBaseUrl.value ??
      'https://mbokashopping.online/';
  static String get referralBaseUrl =>
      // _tryGetContactController()?.referralBaseUrl.value ??
      '${appBaseUrl}referral';
  static String get privacyPolicyUrl =>
      // _tryGetContactController()?.privacyPolicyUrl.value ??
      'https://mbokaadmin.web.app/privacy-policy';
  static String get termsOfServiceUrl =>
      // _tryGetContactController()?.termsOfServiceUrl.value ??
      'https://mbokaadmin.web.app/terms-of-service';

  // Placeholder Images (now dynamic from Firebase)
  static String get placeholderImageBaseUrl =>
      // _tryGetContactController()?.placeholderImageBaseUrl.value ??
      'https://via.placeholder.com';
  static String get defaultPlaceholderImage =>
      // _tryGetContactController()?.defaultPlaceholderImage.value ??
      '${placeholderImageBaseUrl}/150';
  static String categoryPlaceholderImage(String name) =>
      '${placeholderImageBaseUrl}/150?text=${name.replaceAll(' ', '+')}';

  // Product Share URLs (already dynamic)
  static String get productShareBaseUrl =>
      // _tryGetContactController()?.productShareBaseUrl.value ??
      'https://mbokashopping.online/product';

  static String get msosiFoodShareBaseUrl => '${appBaseUrl}msosi/food';
  static String get msosiRestaurantShareBaseUrl =>
      '${appBaseUrl}msosi/restaurant';

  // Contact Information - Now dynamic from Firebase
  static String get supportEmail =>
      // _tryGetContactController()?.supportEmail.value ??
      'lidoxcoltd@example.com';
  static String get companyEmail =>
      // _tryGetContactController()?.companyEmail.value ?? 'lidoxcoltd@gmail.com';
      'lidoxcoltd@gmail.com';
  static String get supportPhone =>
      // _tryGetContactController()?.supportPhone.value ?? '+255655900595';
      '+255655900595';
  static String get supportPhoneName =>
      // _tryGetContactController()?.supportPhoneName.value ??
      'Mboka Huduma Kwa Wateja';
  static String get companyPhonePlaceholder =>
      // _tryGetContactController()?.companyPhonePlaceholder.value ??
      '+XXX XXX XXXX';

  // Phone Number Defaults and Validation
  static const String defaultCountryCode = '+255';
  static const String phoneValidationExample = '+255712345678';

  // Firebase Auth Domain
  static const String firebaseAuthDomain = 'mbokashopping.firebaseapp.com';

  // Current app version (update when releasing new builds)
  // Format: major.minor.patch (plus build number optional) e.g. '1.0.0+1'
  static const String appVersion = '1.0.27';

  // Sample/Test Data URLs (for development/testing only)
  static const String exampleWebsiteUrl = 'https://mbokashopping.online/';
  static const List<String> sampleProductImages = [];
}
