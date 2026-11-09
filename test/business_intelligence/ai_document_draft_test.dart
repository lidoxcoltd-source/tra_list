import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/business_intelligence/ai_document_draft.dart';

void main() {
  test('parses invoice fields without inventing values', () {
    final draft = parseAiDocumentDraft(
      'niandalie invoice; mteja: Asha; bidhaa: Mchele; idadi: 2; bei: 5,000',
    )!;
    expect(draft.kind, AiDocumentKind.invoice);
    expect(draft.customer, 'Asha');
    expect(draft.description, 'Mchele');
    expect(draft.quantity, 2);
    expect(draft.unitPrice, 5000);
    expect(draft.tax, isNull);
  });

  test('routes supported documents and leaves missing fields blank', () {
    final invoice = parseAiDocumentDraft('nitengenezee Invoice');
    expect(invoice?.kind, AiDocumentKind.invoice);
    expect(invoice?.customer, isNull);
    expect(
      parseAiDocumentDraft('andaa quotation')!.kind,
      AiDocumentKind.quotation,
    );
    expect(
      parseAiDocumentDraft('prepare proforma invoice')!.kind,
      AiDocumentKind.proforma,
    );
    final advance = parseAiDocumentDraft(
      'create advance payment invoice; subtotal: 10000; tax: 500; advance: 2000',
    )!;
    expect(advance.kind, AiDocumentKind.advance);
    expect(advance.subtotal, 10000);
    expect(advance.tax, 500);
    expect(advance.advancePaid, 2000);
    expect(
      parseAiDocumentDraft('tengeneza risiti')!.kind,
      AiDocumentKind.receipt,
    );
    expect(parseAiDocumentDraft('tengeneza risiti')!.customer, isNull);
    expect(parseAiDocumentDraft('nipe invoice ya mwisho'), isNull);
  });

  test(
    'preserves a requested receipt amount without inventing item or tax',
    () {
      final draft = parseAiDocumentDraft('sawa tengeneza receipt ya 30,000')!;
      expect(draft.kind, AiDocumentKind.receipt);
      expect(draft.requestedAmount, 30000);
      expect(draft.description, isNull);
      expect(draft.unitPrice, isNull);
      expect(draft.tax, isNull);
      expect(
        parseAiDocumentDraft('create receipt for TZS 1250.50')?.requestedAmount,
        1250.50,
      );
      for (final input in [
        'sawa tengeneza receipt ya 12,34',
        'tengeneza risiti ya 0',
        'tengeneza risiti ya 1000000000001',
        'tengeneza risiti ya 30000; mteja: Asha',
      ]) {
        expect(
          () => parseAiDocumentDraft(input),
          throwsFormatException,
          reason: input,
        );
      }
    },
  );

  test(
    'rejects ambiguous or ignored information rather than inventing fields',
    () {
      for (final input in [
        'niandalie invoice ya Asha',
        'niandalie invoice; mteja: Asha; mteja: Juma',
        'niandalie invoice; bidhaa: Mchele; bei: 5000',
        'niandalie invoice; bidhaa: Mchele; idadi: 2; bei: 12,34',
        'niandalie invoice; kodi: 500',
        'niandalie risiti; bidhaa: Mchele; idadi: 1.5; bei: 2000',
        'niandalie advance; bidhaa: Mchele',
      ]) {
        expect(
          () => parseAiDocumentDraft(input),
          throwsFormatException,
          reason: input,
        );
      }
    },
  );
}
