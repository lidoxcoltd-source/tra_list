class VoiceTransactionDraft {
  const VoiceTransactionDraft({
    required this.type,
    required this.amount,
    required this.category,
    required this.description,
  });

  final String type;
  final int amount;
  final String category;
  final String description;

  factory VoiceTransactionDraft.fromArguments(Map<dynamic, dynamic> args) {
    const keys = {'type', 'amount', 'category', 'description'};
    if (args.keys.any((key) => key is! String || !keys.contains(key))) {
      throw const FormatException('Unsupported transaction field');
    }
    final type = args['type'];
    final amount = args['amount'];
    if ((type != 'income' && type != 'expense') ||
        amount is! num ||
        !amount.isFinite ||
        amount <= 0 ||
        amount > 1000000000000 ||
        amount != amount.roundToDouble()) {
      throw const FormatException('Invalid transaction type or amount');
    }
    String field(String key, int limit) {
      final value = args[key];
      if (value is! String ||
          value.trim().isEmpty ||
          value.trim().length > limit ||
          RegExp(r'[;\r\n]').hasMatch(value)) {
        throw const FormatException('Invalid transaction field');
      }
      return value.trim();
    }

    return VoiceTransactionDraft(
      type: type as String,
      amount: amount.toInt(),
      category: field('category', 100),
      description: field('description', 300),
    );
  }

  String get chatCommand =>
      'record $type $amount; category: $category; description: $description';
}
