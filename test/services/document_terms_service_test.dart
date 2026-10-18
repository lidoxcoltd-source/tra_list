import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/services/document_terms_service.dart';

void main() {
  group('DocumentTermsService', () {
    test('uses built-in wording if no version is selected', () {
      final terms = DocumentTermsService.selectedFor({}, 'invoice');

      expect(terms['name'], 'Built-in default');
      expect(terms['note'], DocumentTermsService.defaultNote);
      expect(terms['delivery'], DocumentTermsService.defaultDelivery);
      expect(terms['conditions'], isEmpty);
    });

    test('keeps the advance payment default wording', () {
      final terms = DocumentTermsService.selectedFor({}, 'advance_payment');

      expect(terms['note'], DocumentTermsService.defaultAdvancePaymentNote);
    });

    test('returns the selected version for a document type', () {
      final profile = {
        'documentTermsVersions': [
          {
            'id': 'standard-v2',
            'name': 'Standard v2',
            'note': 'Payment due on completion.',
            'delivery': 'Delivery within 10 days.',
            'conditions': 'Warranty applies.',
          },
        ],
        'selectedDocumentTerms': {
          'invoice': 'standard-v2',
          'quotation': 'missing-version',
        },
      };

      final invoiceTerms = DocumentTermsService.selectedFor(profile, 'invoice');
      final quotationTerms = DocumentTermsService.selectedFor(
        profile,
        'quotation',
      );

      expect(invoiceTerms['name'], 'Standard v2');
      expect(invoiceTerms['conditions'], 'Warranty applies.');
      expect(quotationTerms['name'], 'Built-in default');
      expect(quotationTerms['note'], DocumentTermsService.defaultNote);
    });

    test('defaults missing fields in an older saved version', () {
      final terms = DocumentTermsService.selectedFor({
        'documentTermsVersions': [
          {'id': 'legacy', 'name': 'Legacy'},
        ],
        'selectedDocumentTerms': {'proforma': 'legacy'},
      }, 'proforma');

      expect(terms['note'], DocumentTermsService.defaultNote);
      expect(terms['delivery'], DocumentTermsService.defaultDelivery);
      expect(terms['conditions'], isEmpty);
    });
  });
}
