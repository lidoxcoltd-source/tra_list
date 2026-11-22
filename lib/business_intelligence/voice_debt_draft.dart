import 'package:tra_list/jobs/models/debt.dart';

class VoiceDebtDraft {
  const VoiceDebtDraft({
    required this.debtorName,
    required this.amount,
    required this.direction,
    required this.reason,
    required this.notes,
    required this.dueDate,
  });

  final String debtorName;
  final double amount;
  final DebtDirection direction;
  final String reason;
  final String notes;
  final DateTime? dueDate;

  factory VoiceDebtDraft.fromArguments(Map<dynamic, dynamic> args) {
    const keys = {
      'debtor_name',
      'amount',
      'direction',
      'reason',
      'due_date',
      'notes',
    };
    if (args.keys.any((key) => key is! String || !keys.contains(key))) {
      throw const FormatException('Unsupported debt field');
    }

    final debtorName = args['debtor_name'];
    final amount = args['amount'];
    final direction = switch (args['direction']) {
      'customerOwesShop' => DebtDirection.customerOwesShop,
      'shopOwesOther' => DebtDirection.shopOwesOther,
      _ => throw const FormatException('Invalid debt direction'),
    };
    final rawReason = args['reason'] ?? 'other';
    const reasons = {'advance', 'goods_credit', 'service', 'other'};
    if (debtorName is! String ||
        debtorName.trim().isEmpty ||
        debtorName.trim().length > 120 ||
        amount is! num ||
        !amount.isFinite ||
        amount <= 0 ||
        amount > 1000000000000 ||
        rawReason is! String ||
        !reasons.contains(rawReason)) {
      throw const FormatException('Invalid debt details');
    }

    final rawNotes = args['notes'] ?? '';
    if (rawNotes is! String || rawNotes.trim().length > 300) {
      throw const FormatException('Invalid debt notes');
    }

    final rawDueDate = args['due_date'];
    DateTime? dueDate;
    if (rawDueDate != null) {
      if (rawDueDate is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDueDate)) {
        throw const FormatException('Invalid debt due date');
      }
      final parsed = DateTime.tryParse(rawDueDate);
      if (parsed == null ||
          '${parsed.year.toString().padLeft(4, '0')}-'
                  '${parsed.month.toString().padLeft(2, '0')}-'
                  '${parsed.day.toString().padLeft(2, '0')}' !=
              rawDueDate) {
        throw const FormatException('Invalid debt due date');
      }
      dueDate = parsed;
    }

    return VoiceDebtDraft(
      debtorName: debtorName.trim(),
      amount: amount.toDouble(),
      direction: direction,
      reason: rawReason,
      notes: rawNotes.trim(),
      dueDate: dueDate,
    );
  }
}
