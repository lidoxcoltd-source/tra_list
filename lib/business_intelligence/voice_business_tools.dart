import 'package:flutter/foundation.dart';
import 'package:tra_list/business_intelligence/ai_provider.dart';
import 'package:tra_list/business_intelligence/ai_document_draft.dart';
import 'package:tra_list/business_intelligence/business_context.dart';
import 'package:tra_list/business_intelligence/voice_transaction_draft.dart';
import 'package:tra_list/business_intelligence/isher_navigation.dart';
import 'package:tra_list/jobs/models/debt.dart';
import 'package:tra_list/jobs/services/debt_service.dart';

typedef VoiceToolHandler =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<dynamic, dynamic> args,
    );

class VoiceBusinessTools {
  VoiceBusinessTools({
    required this.provider,
    required this.business,
    required this.isCurrent,
    this.initialSnapshot,
    this.onDocument,
    this.onTransaction,
    this.onNavigate,
    this.onSummary,
    this.onSummaryLoading,
    this.onDebtReminder,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AIProvider provider;
  final BusinessContext business;
  final bool Function() isCurrent;
  final AiSnapshot? initialSnapshot;
  final void Function(AiDocumentDraft draft)? onDocument;
  final Future<void> Function(VoiceTransactionDraft draft)? onTransaction;
  final Future<bool> Function(IsherDestination destination)? onNavigate;
  final void Function(Map<String, dynamic> summary)? onSummary;
  final void Function(bool loading)? onSummaryLoading;
  final Future<bool> Function(Debt debt, String message)? onDebtReminder;
  final DateTime Function() _clock;
  bool _documentRequested = false;

  Future<Map<String, dynamic>> call(
    String name,
    Map<dynamic, dynamic> args,
  ) async {
    try {
      if (name == 'get_business_summary') {
        return {'summary': await businessSummary(args)};
      }
      if (name == 'get_document_details') {
        return {'details': await documentDetails(args)};
      }
      if (name == 'get_current_debts') {
        if (!isCurrent()) throw StateError('Business access changed');
        if (args.keys.any((key) => key != 'due_within_days' && key != 'overdue_only')) {
          throw const FormatException('Unsupported debt filter');
        }
        final days = args['due_within_days'];
        final overdueOnly = args['overdue_only'] ?? false;
        if ((days != null && (days is! int || days < 0 || days > 365)) || overdueOnly is! bool) {
          throw const FormatException('Invalid debt filter');
        }
        final now = _clock();
        final today = DateTime(now.year, now.month, now.day);
        final lookAheadDays = days == null ? 365 : days as int;
        final end = today.add(Duration(days: lookAheadDays));
        final debts = await DebtService.loadForAssistant();
        final matchingDebts = debts.where((debt) {
          if (debt.isSettled) return false;
          if (overdueOnly) return debt.isOverdue;
          if (days != null) {
            return debt.dueDate != null &&
                !DateTime(debt.dueDate!.year, debt.dueDate!.month, debt.dueDate!.day).isBefore(today) &&
                !DateTime(debt.dueDate!.year, debt.dueDate!.month, debt.dueDate!.day).isAfter(end);
          }
          return true;
        }).toList(growable: false);
        final results = matchingDebts.take(50).map((debt) => {
          'id': debt.id,
          'name': debt.debtorName,
          'balance': debt.balance,
          'direction': debt.direction.name,
          'dueDate': debt.dueDate?.toIso8601String().substring(0, 10),
          'overdue': debt.isOverdue,
        }).toList(growable: false);
        return {
          'debts': results,
          'count': results.length,
          'truncated': matchingDebts.length > results.length || debts.length >= 100,
        };
      }
      if (name == 'review_whatsapp_debt_reminder') {
        if (!isCurrent() || onDebtReminder == null ||
            args.keys.any((key) => key != 'debt_id' && key != 'message')) {
          throw StateError('Reminder review unavailable');
        }
        final id = args['debt_id'];
        final message = args['message'];
        if (id is! String || id.isEmpty || id.length > 128 ||
            message is! String || message.trim().isEmpty || message.length > 1000) {
          throw const FormatException('Invalid reminder draft');
        }
        final debt = await DebtService.loadAssistantDebt(id);
        if (debt == null || debt.isSettled || debt.phone.trim().isEmpty ||
            debt.direction != DebtDirection.customerOwesShop) {
          throw StateError('Debtor or WhatsApp number is unavailable');
        }
        final approved = await onDebtReminder!(debt, message.trim());
        return {'status': approved
            ? 'The approved message was opened in WhatsApp. The user must press Send there; do not say it was sent.'
            : 'The user cancelled. Do not claim WhatsApp opened or the message was sent.'};
      }
      if (name == 'review_transaction_draft') {
        if (!isCurrent() || onTransaction == null) {
          throw StateError('Transaction review unavailable');
        }
        final draft = VoiceTransactionDraft.fromArguments(args);
        await onTransaction!(draft);
        return {
          'status':
              'Review closed. The transaction is not saved by voice. If confirmed, the request proceeds in chat; check chat for the result.',
        };
      }
      if (name == 'open_app_page') {
        if (!isCurrent() ||
            onNavigate == null ||
            args.length != 1 ||
            args['destination'] is! String) {
          throw StateError('Page navigation unavailable');
        }
        final destination = IsherDestination.values
            .where((item) => item.name == args['destination'])
            .firstOrNull;
        if (destination == null) throw const FormatException('Unknown page');
        final opened = await onNavigate!(destination);
        return {
          'status': opened
              ? 'The user confirmed the navigation request.'
              : 'Navigation was cancelled or unavailable. Do not claim it opened.',
        };
      }
      if (name == 'open_document_draft') {
        if (!isCurrent() || onDocument == null || _documentRequested) {
          throw StateError('Document form unavailable');
        }
        final draft = voiceDocumentDraft(args);
        _documentRequested = true;
        onDocument!(draft);
        return {'status': 'Opening review only; the document is not saved.'};
      }
      return {'error': 'Unknown tool. Do not guess.'};
    } catch (error, stack) {
      debugPrint('Voice business tool failed: ${error.runtimeType}');
      debugPrintStack(stackTrace: stack);
      return {
        'error':
            'The requested action failed. Do not guess or claim it succeeded.',
      };
    }
  }

  AiDocumentDraft voiceDocumentDraft(Map<dynamic, dynamic> args) {
    const allowed = {
      'kind',
      'customer',
      'description',
      'quantity',
      'unit_price',
      'subtotal',
      'tax',
      'advance_paid',
      'items',
    };
    if (args.keys.any((key) => key is! String || !allowed.contains(key))) {
      throw const FormatException('Unsupported document field');
    }
    final kind = switch (args['kind']) {
      'invoice' => AiDocumentKind.invoice,
      'receipt' => AiDocumentKind.receipt,
      'quotation' => AiDocumentKind.quotation,
      'proforma' => AiDocumentKind.proforma,
      'advance' => AiDocumentKind.advance,
      _ => throw const FormatException('Unknown document type'),
    };
    String? text(String key) {
      final value = args[key];
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty || value.length > 200) {
        throw const FormatException('Invalid document text');
      }
      return value.trim();
    }

    double? number(String key, {bool allowZero = false}) {
      final value = args[key];
      if (value == null) return null;
      if (value is! num ||
          !value.isFinite ||
          value > 1000000000000 ||
          (allowZero ? value < 0 : value <= 0)) {
        throw const FormatException('Invalid document amount');
      }
      return value.toDouble();
    }

    final customer = text('customer');
    final description = text('description');
    final quantity = number('quantity');
    final unitPrice = number('unit_price');
    final subtotal = number('subtotal', allowZero: true);
    final tax = number('tax', allowZero: true);
    final advancePaid = number('advance_paid', allowZero: true);
    final rawItems = args['items'];
    final invoiceItems = <AiInvoiceItem>[];
    if (rawItems != null) {
      if (rawItems is! List ||
          rawItems.isEmpty ||
          rawItems.length > 30 ||
          kind == AiDocumentKind.receipt ||
          kind == AiDocumentKind.advance ||
          description != null ||
          quantity != null ||
          unitPrice != null) {
        throw const FormatException('Unsupported document items');
      }
      for (final item in rawItems) {
        if (item is! Map ||
            item.keys.any(
              (key) =>
                  key != 'description' &&
                  key != 'quantity' &&
                  key != 'unit_price',
            )) {
          throw const FormatException('Invalid item');
        }
        final itemDescription = item['description'];
        final itemQuantity = item['quantity'];
        final itemPrice = item['unit_price'];
        if (itemDescription is! String ||
            itemDescription.trim().isEmpty ||
            itemDescription.length > 200 ||
            itemQuantity is! num ||
            !itemQuantity.isFinite ||
            itemQuantity <= 0 ||
            itemQuantity > 1000000000000 ||
            itemPrice is! num ||
            !itemPrice.isFinite ||
            itemPrice <= 0 ||
            itemPrice > 1000000000000 ||
            itemQuantity * itemPrice > 1000000000000) {
          throw const FormatException('Invalid item');
        }
        invoiceItems.add(
          AiInvoiceItem(
            description: itemDescription.trim(),
            quantity: itemQuantity.toDouble(),
            unitPrice: itemPrice.toDouble(),
          ),
        );
      }
    }
    final itemFields = [description, quantity, unitPrice].whereType<Object>();
    if (itemFields.isNotEmpty && itemFields.length != 3) {
      throw const FormatException('Incomplete item');
    }
    if (kind == AiDocumentKind.receipt &&
        quantity != null &&
        quantity != quantity.roundToDouble()) {
      throw const FormatException('Invalid receipt quantity');
    }
    if (kind == AiDocumentKind.advance) {
      if (description != null) throw const FormatException('Invalid item');
    } else if (subtotal != null ||
        advancePaid != null ||
        (tax != null && kind != AiDocumentKind.receipt)) {
      throw const FormatException('Unsupported document fields');
    }
    return AiDocumentDraft(
      kind: kind,
      customer: customer,
      description: description,
      quantity: quantity,
      unitPrice: unitPrice,
      subtotal: subtotal,
      tax: tax,
      advancePaid: advancePaid,
      invoiceItems: invoiceItems,
    );
  }

  Future<Map<String, dynamic>> documentDetails(
    Map<dynamic, dynamic> args,
  ) async {
    if (!isCurrent()) throw StateError('Business access changed');
    final question = args['question'];
    if (question is! String ||
        question.trim().isEmpty ||
        question.length > 2000) {
      throw const FormatException('Invalid document question');
    }
    final Object documentProvider = provider;
    if (documentProvider is! AiDocumentReviewProvider) {
      throw StateError('Document details unavailable');
    }
    final period = _period(args);
    final context = business.withPeriod(period);
    final snapshot = await provider.prepare(context);
    if (!isCurrent()) throw StateError('Business access changed');
    final review = await documentProvider.prepareDocumentReview(
      context: context,
      snapshot: snapshot,
      question: question,
    );
    if (!isCurrent()) throw StateError('Business access changed');
    if (review == null) throw StateError('Document details unavailable');
    return review.details;
  }

  Future<Map<String, dynamic>> businessSummary(
    Map<dynamic, dynamic> args,
  ) async {
    if (!isCurrent()) throw StateError('Business access changed');
    final period = _period(args);
    onSummaryLoading?.call(true);
    try {
      final snapshot =
          _reusableSnapshot(period) ??
          await provider.prepare(business.withPeriod(period));
      if (!isCurrent()) throw StateError('Business access changed');
      final summary = snapshot.context;
      onSummary?.call(summary);
      return summary;
    } finally {
      onSummaryLoading?.call(false);
    }
  }

  AiSnapshot? _reusableSnapshot(ReportingPeriod period) {
    final snapshot = initialSnapshot;
    final updatedAtValue = snapshot?.context['updatedAt'];
    if (snapshot == null ||
        period.start != business.period.start ||
        period.end != business.period.end ||
        updatedAtValue is! String) {
      return null;
    }
    final updatedAt = DateTime.tryParse(updatedAtValue);
    if (updatedAt == null) return null;
    final age = _clock().toUtc().difference(updatedAt.toUtc());
    return age >= Duration.zero && age <= const Duration(minutes: 1)
        ? snapshot
        : null;
  }

  ReportingPeriod _period(Map<dynamic, dynamic> args) {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final period = switch (args['period']) {
      'today' ||
      'yesterday' ||
      'seven' ||
      'thirty' ||
      'month' ||
      'previous' => ReportingPeriod.fromKey(args['period'] as String, now),
      'selected' => business.period,
      'custom' => _customPeriod(args, today),
      _ => throw const FormatException('Unknown reporting period'),
    };
    if (period.end.difference(period.start) > const Duration(days: 366) ||
        period.start.isAfter(today) ||
        period.end.isAfter(DateTime(today.year, today.month, today.day + 1))) {
      throw const FormatException('Invalid reporting period');
    }
    return period;
  }

  ReportingPeriod _customPeriod(Map<dynamic, dynamic> args, DateTime today) {
    DateTime parse(Object? value) {
      if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        throw const FormatException('Invalid date');
      }
      final date = DateTime.tryParse(value);
      if (date == null ||
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' !=
              value ||
          date.isBefore(DateTime(1970)) ||
          date.isAfter(today)) {
        throw const FormatException('Invalid date');
      }
      return date;
    }

    final start = parse(args['start_date']);
    final lastDay = parse(args['end_date']);
    if (lastDay.isBefore(start)) throw const FormatException('Invalid range');
    return ReportingPeriod(
      start,
      DateTime(lastDay.year, lastDay.month, lastDay.day + 1),
    );
  }
}
