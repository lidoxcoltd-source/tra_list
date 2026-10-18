import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/profile_service.dart';

class DocumentTermsService {
  DocumentTermsService._();

  static const defaultNote =
      "We kindly request that the remaining balance to be settled upon the project's completion.\n"
      'This will help ensure that everything runs smoothly and\n'
      'allows us to maintain the highest quality of service.';
  static const defaultDelivery =
      'Delivery Time  Max 7 Days Min 5 Days\nFrom Payment Day';
  static const defaultAdvancePaymentNote =
      'We kindly request that the remaining balance be settled upon project completion. '
      'This ensures smooth delivery and maintains our quality of service.';

  static const documentTypes = <String, String>{
    'invoice': 'Invoice',
    'proforma': 'Proforma',
    'quotation': 'Quotation',
    'advance_payment': 'Advance Payment',
  };

  static Map<String, dynamic> defaultVersion({
    String documentType = 'invoice',
  }) => {
    'name': 'Built-in default',
    'note': documentType == 'advance_payment'
        ? defaultAdvancePaymentNote
        : defaultNote,
    'delivery': defaultDelivery,
    'conditions': '',
  };

  static Map<String, dynamic> selectedFor(
    Map<String, dynamic> profile,
    String documentType,
  ) {
    final selected = Map<String, dynamic>.from(
      profile['selectedDocumentTerms'] as Map? ?? const {},
    );
    final selectedId = selected[documentType]?.toString() ?? '';
    final versions = (profile['documentTermsVersions'] as List? ?? const [])
        .whereType<Map>()
        .map((version) => Map<String, dynamic>.from(version));
    for (final version in versions) {
      if (version['id']?.toString() == selectedId && selectedId.isNotEmpty) {
        return _withDefaults(version, documentType);
      }
    }
    return defaultVersion(documentType: documentType);
  }

  static Future<Map<String, dynamic>> applySelected(
    Map<String, dynamic> data,
    String documentType,
  ) async {
    final company = Map<String, dynamic>.from(data['company'] as Map? ?? {});
    var profile = company;
    if (BusinessAccessService.canReadBusinessProfile()) {
      profile = await ProfileService.loadOrCreate();
    }
    return {...data, 'documentTerms': selectedFor(profile, documentType)};
  }

  static Map<String, dynamic> _withDefaults(
    Map<String, dynamic> version,
    String documentType,
  ) => {...defaultVersion(documentType: documentType), ...version};
}
