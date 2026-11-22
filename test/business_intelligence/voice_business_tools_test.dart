import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/business_intelligence/ai_document_draft.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/voice_business_tools.dart';
import 'package:tra_list/business_intelligence/voice_debt_draft.dart';
import 'package:tra_list/business_intelligence/isher_navigation.dart';
import 'package:tra_list/jobs/models/debt.dart';

class _Provider implements AIProvider {
  BusinessContext? requested;
  Completer<AiSnapshot>? nextPreparation;
  var preparations = 0;
  bool fail = false;

  @override
  Future<AiSnapshot> prepare(BusinessContext context) async {
    preparations++;
    requested = context;
    final pending = nextPreparation;
    nextPreparation = null;
    if (pending != null) return pending.future;
    if (fail) throw StateError('unavailable');
    return const AiSnapshot({
      'pos': {'total': 12345},
    }, 'secret-token');
  }

  @override
  Future<String> respond({
    required BusinessContext context,
    required AiSnapshot snapshot,
    required List<Map<String, String>> messages,
    required String language,
    String? messageId,
  }) => throw UnimplementedError();
}

class _DocumentProvider extends _Provider implements AiDocumentReviewProvider {
  String? question;

  @override
  Future<AiDocumentReview?> prepareDocumentReview({
    required BusinessContext context,
    required AiSnapshot snapshot,
    required String question,
  }) async {
    this.question = question;
    return const AiDocumentReview({
      'invoices': [
        {'number': 'INV-1', 'total': 10000},
      ],
    }, 'private-document-token');
  }
}

void main() {
  final business = BusinessContext(
    businessId: 'business',
    businessName: 'Duka',
    period: ReportingPeriod(DateTime(2026, 11, 1), DateTime(2026, 11, 10)),
    updatedAt: DateTime(2026, 11, 9),
    income: 0,
    expenses: 0,
    transactionCount: 0,
    expenseCategories: const {},
    lowStock: null,
    receivable: null,
    payable: null,
    limitations: const [],
  );
  late _Provider provider;
  late VoiceBusinessTools tools;
  var current = true;
  setUp(() {
    provider = _Provider();
    current = true;
    tools = VoiceBusinessTools(
      provider: provider,
      business: business,
      isCurrent: () => current,
      clock: () => DateTime(2026, 11, 9, 12),
    );
  });

  test(
    'navigation only accepts allowed destinations and current access',
    () async {
      IsherDestination? requested;
      tools = VoiceBusinessTools(
        provider: provider,
        business: business,
        isCurrent: () => current,
        onNavigate: (destination) async {
          requested = destination;
          return true;
        },
      );
      expect(
        await tools.call('open_app_page', {'destination': 'tasks'}),
        containsPair('status', contains('confirmed')),
      );
      expect(requested, IsherDestination.tasks);
      requested = null;
      expect(
        await tools.call('open_app_page', {'destination': '/admin'}),
        contains('error'),
      );
      expect(
        await tools.call('open_app_page', {
          'destination': 'tasks',
          'route': '/admin',
        }),
        contains('error'),
      );
      current = false;
      expect(
        await tools.call('open_app_page', {'destination': 'tasks'}),
        contains('error'),
      );
      expect(requested, isNull);
    },
  );

  test(
    'yesterday fetches the authorized exact local day and omits token',
    () async {
      Map<String, dynamic>? shownSummary;
      tools = VoiceBusinessTools(
        provider: provider,
        business: business,
        isCurrent: () => current,
        onSummary: (summary) => shownSummary = summary,
        clock: () => DateTime(2026, 11, 9, 12),
      );
      final result = await tools.call('get_business_summary', {
        'period': 'yesterday',
      });
      expect(provider.requested!.period.start, DateTime(2026, 11, 8));
      expect(provider.requested!.period.end, DateTime(2026, 11, 9));
      expect(result, {
        'summary': {
          'pos': {'total': 12345},
        },
      });
      expect(shownSummary, {
        'pos': {'total': 12345},
      });
      expect(result.toString(), isNot(contains('secret-token')));
    },
  );

  test(
    'fresh same-period snapshot is reused but another period is fetched',
    () async {
      final snapshot = AiSnapshot({
        'businessName': 'Duka',
        'updatedAt': DateTime(
          2026,
          11,
          9,
          11,
          59,
          30,
        ).toUtc().toIso8601String(),
      }, 'snapshot-token');
      tools = VoiceBusinessTools(
        provider: provider,
        business: business,
        isCurrent: () => current,
        initialSnapshot: snapshot,
        clock: () => DateTime(2026, 11, 9, 12),
      );

      final selected = await tools.businessSummary({'period': 'selected'});
      expect(selected, snapshot.context);
      expect(provider.preparations, 0);

      await tools.businessSummary({'period': 'yesterday'});
      expect(provider.preparations, 1);
      expect(provider.requested!.period.start, DateTime(2026, 11, 8));
    },
  );

  test(
    'report loading callback remains active until fresh data is ready',
    () async {
      final loadingStates = <bool>[];
      final pending = Completer<AiSnapshot>();
      provider.nextPreparation = pending;
      tools = VoiceBusinessTools(
        provider: provider,
        business: business,
        isCurrent: () => current,
        onSummaryLoading: loadingStates.add,
        clock: () => DateTime(2026, 11, 9, 12),
      );

      final request = tools.businessSummary({'period': 'yesterday'});
      expect(loadingStates, [true]);
      pending.complete(
        const AiSnapshot({'businessName': 'Duka'}, 'fresh-token'),
      );
      await request;
      expect(loadingStates, [true, false]);
    },
  );

  test(
    'custom dates are inclusive and invalid or future dates are rejected',
    () async {
      await tools.businessSummary({
        'period': 'custom',
        'start_date': '2026-10-30',
        'end_date': '2026-11-02',
      });
      expect(provider.requested!.period.end, DateTime(2026, 11, 3));
      for (final date in ['2026-02-30', '2026-11-10', '2026-1-01']) {
        expect(
          () => tools.businessSummary({
            'period': 'custom',
            'start_date': date,
            'end_date': date,
          }),
          throwsFormatException,
        );
      }
    },
  );
  test('voice draft carries supplied values and never saves', () async {
    AiDocumentDraft? opened;
    tools = VoiceBusinessTools(
      provider: provider,
      business: business,
      isCurrent: () => current,
      onDocument: (draft) => opened = draft,
    );
    final result = await tools.call('open_document_draft', {
      'kind': 'invoice',
      'customer': 'Mteja',
      'description': 'Bidhaa',
      'quantity': 2,
      'unit_price': 12500,
    });
    expect(result['status'], contains('not saved'));
    expect(opened!.kind, AiDocumentKind.invoice);
    expect(opened!.customer, 'Mteja');
    expect(opened!.quantity, 2);
    expect(opened!.unitPrice, 12500);
    expect(provider.requested, isNull);
  });

  test(
    'invalid and unauthorized document requests do not open a form',
    () async {
      var opens = 0;
      tools = VoiceBusinessTools(
        provider: provider,
        business: business,
        isCurrent: () => current,
        onDocument: (_) => opens++,
      );
      for (final args in [
        {
          'kind': 'receipt',
          'description': 'Bidhaa',
          'quantity': 1.5,
          'unit_price': 10,
        },
        {'kind': 'invoice', 'description': 'Bidhaa'},
        {
          'kind': 'invoice',
          'description': 'Bidhaa',
          'quantity': -1,
          'unit_price': 10,
        },
        {'kind': 'invoice', 'tax': 10},
        {'kind': 'unknown'},
      ]) {
        expect(
          (await tools.call('open_document_draft', args))['error'],
          isNotNull,
        );
      }
      current = false;
      expect(
        (await tools.call('open_document_draft', {'kind': 'receipt'}))['error'],
        isNotNull,
      );
      expect(opens, 0);
    },
  );

  test(
    'access changes and provider failures return errors instead of numbers',
    () async {
      current = false;
      expect(
        (await tools.call('get_business_summary', {
          'period': 'today',
        }))['error'],
        isNotNull,
      );
      expect(provider.requested, isNull);
      current = true;
      provider.fail = true;
      expect(
        (await tools.call('get_business_summary', {
          'period': 'today',
        }))['error'],
        isNotNull,
      );
      expect((await tools.call('unrecognized', {}))['error'], isNotNull);
    },
  );

  test(
    'a business change while preparing a summary prevents disclosure',
    () async {
      final pending = tools.call('get_business_summary', {
        'period': 'yesterday',
      });
      current = false;
      final result = await pending;
      expect(result['error'], isNotNull);
      expect(result.containsKey('summary'), isFalse);
    },
  );

  test('voice transaction calls review only and does not save', () async {
    var reviewCount = 0;
    tools = VoiceBusinessTools(
      provider: provider,
      business: business,
      isCurrent: () => current,
      onTransaction: (draft) async {
        reviewCount++;
        expect(draft.amount, 10000);
        expect(draft.category, 'Kodi');
      },
    );
    final result = await tools.call('review_transaction_draft', {
      'type': 'expense',
      'amount': 10000,
      'category': 'Kodi',
      'description': 'Kodi ya duka',
    });
    expect(reviewCount, 1);
    expect(result['status'], contains('not saved'));
    expect(provider.requested, isNull);
    current = false;
    final denied = await tools.call('review_transaction_draft', {
      'type': 'expense',
      'amount': 10000,
      'category': 'Kodi',
      'description': 'Kodi ya duka',
    });
    expect(denied['error'], isNotNull);
    expect(reviewCount, 1);
  });

  test('confirmed voice debt is saved through the registration callback', () async {
    VoiceDebtDraft? savedDraft;
    tools = VoiceBusinessTools(
      provider: provider,
      business: business,
      isCurrent: () => current,
      onRecordDebt: (draft) async {
        savedDraft = draft;
      },
    );
    final result = await tools.call('record_debt', {
      'debtor_name': 'Asha',
      'amount': 45000,
      'direction': 'customerOwesShop',
      'reason': 'goods_credit',
      'due_date': '2026-11-30',
      'notes': 'Atalipa mwisho wa mwezi',
    });

    expect(result['status'], contains('saved successfully'));
    expect(savedDraft!.debtorName, 'Asha');
    expect(savedDraft!.amount, 45000);
    expect(savedDraft!.direction, DebtDirection.customerOwesShop);
    expect(savedDraft!.reason, 'goods_credit');
    expect(savedDraft!.dueDate, DateTime(2026, 11, 30));
    expect(savedDraft!.notes, 'Atalipa mwisho wa mwezi');
  });

  test('invalid or stale voice debt requests are not saved', () async {
    var saves = 0;
    tools = VoiceBusinessTools(
      provider: provider,
      business: business,
      isCurrent: () => current,
      onRecordDebt: (_) async {
        saves++;
      },
    );
    for (final args in [
      {
        'debtor_name': 'Asha',
        'amount': 0,
        'direction': 'customerOwesShop',
        'reason': 'other',
      },
      {
        'debtor_name': 'Asha',
        'amount': 45000,
        'direction': 'unknown',
        'reason': 'other',
      },
      {
        'debtor_name': 'Asha',
        'amount': 45000,
        'direction': 'customerOwesShop',
        'reason': 'other',
        'due_date': '2026-02-30',
      },
    ]) {
      expect((await tools.call('record_debt', args))['error'], isNotNull);
    }

    current = false;
    expect(
      (await tools.call('record_debt', {
        'debtor_name': 'Asha',
        'amount': 45000,
        'direction': 'customerOwesShop',
        'reason': 'other',
      }))['error'],
      isNotNull,
    );
    expect(saves, 0);
  });

  test(
    'voice passes multiple invoice items into draft without saving',
    () async {
      AiDocumentDraft? draft;
      tools = VoiceBusinessTools(
        provider: provider,
        business: business,
        isCurrent: () => current,
        onDocument: (value) => draft = value,
      );
      final result = await tools.call('open_document_draft', {
        'kind': 'invoice',
        'items': [
          {'description': 'Mchele', 'quantity': 2, 'unit_price': 5000},
          {'description': 'Mafuta', 'quantity': 1, 'unit_price': 8000},
        ],
      });
      expect(result['status'], contains('not saved'));
      expect(draft!.invoiceItems.map((item) => item.description), [
        'Mchele',
        'Mafuta',
      ]);
      expect(draft!.invoiceItems[1].unitPrice, 8000);
    },
  );

  test('receipt cannot silently drop additional items', () async {
    var opened = false;
    tools = VoiceBusinessTools(
      provider: provider,
      business: business,
      isCurrent: () => current,
      onDocument: (_) => opened = true,
    );
    final result = await tools.call('open_document_draft', {
      'kind': 'receipt',
      'items': [
        {'description': 'A', 'quantity': 1, 'unit_price': 5},
        {'description': 'B', 'quantity': 1, 'unit_price': 5},
      ],
    });
    expect(result['error'], isNotNull);
    expect(opened, isFalse);
  });

  test(
    'document details use existing provider and do not send review token',
    () async {
      final documentProvider = _DocumentProvider();
      tools = VoiceBusinessTools(
        provider: documentProvider,
        business: business,
        isCurrent: () => current,
        clock: () => DateTime(2026, 11, 9, 12),
      );
      final result = await tools.call('get_document_details', {
        'period': 'yesterday',
        'question': 'Nipe invoice ya jana',
      });
      expect(documentProvider.question, 'Nipe invoice ya jana');
      expect(documentProvider.requested!.period.start, DateTime(2026, 11, 8));
      expect(result['details'], {
        'invoices': [
          {'number': 'INV-1', 'total': 10000},
        ],
      });
      expect(result.toString(), isNot(contains('private-document-token')));
    },
  );
}
