enum AiDocumentKind { invoice, quotation, proforma, advance, receipt }

class AiInvoiceItem {
  const AiInvoiceItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.productId,
  });

  final String description;
  final double quantity;
  final double unitPrice;
  final String? productId;
}

class AiDocumentDraft {
  const AiDocumentDraft({
    required this.kind,
    this.customer,
    this.description,
    this.quantity,
    this.unitPrice,
    this.subtotal,
    this.tax,
    this.advancePaid,
    this.requestedAmount,
    this.invoiceName,
    this.invoiceNumber,
    this.issueDate,
    this.dueDate,
    this.terms,
    this.invoiceItems = const [],
  });

  final AiDocumentKind kind;
  final String? customer;
  final String? description;
  final double? quantity;
  final double? unitPrice;
  final double? subtotal;
  final double? tax;
  final double? advancePaid;
  final double? requestedAmount;
  final String? invoiceName;
  final String? invoiceNumber;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final String? terms;
  final List<AiInvoiceItem> invoiceItems;
}

AiDocumentDraft? parseAiDocumentDraft(String input) {
  final sections = input.trim().split(';');
  if (sections.isEmpty) return null;
  var command = sections.first.trim().toLowerCase();
  final receiptRequest = RegExp(
    r'^(?:(?:sawa|ok|okay)[,\s]+)?(?:niandalie|niandae|nitengenezee|tengeneza|andaa|create|prepare|make)\s+(?:receipt|risiti)\s+(?:ya|of|for)\s+(?:(?:tsh|tzs)\s*)?(\S+)$',
  ).firstMatch(command);
  double? requestedAmount;
  if (receiptRequest != null) {
    final raw = receiptRequest[1]!;
    if (!RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$').hasMatch(raw)) {
      throw const FormatException('invalid-number');
    }
    requestedAmount = double.tryParse(raw.replaceAll(',', ''));
    if (requestedAmount == null ||
        !requestedAmount.isFinite ||
        requestedAmount <= 0 ||
        requestedAmount > 1000000000000 ||
        sections.length != 1) {
      throw const FormatException('invalid-number');
    }
    command = 'tengeneza receipt';
  }
  if (!RegExp(
    r'^(?:niandalie|niandae|nitengenezee|tengeneza|andaa|create|prepare|make)\b',
  ).hasMatch(command)) {
    return null;
  }
  final AiDocumentKind? kind;
  if (RegExp(r'\b(?:advance|advance payment)\b').hasMatch(command)) {
    kind = AiDocumentKind.advance;
  } else if (RegExp(r'\bproforma\b').hasMatch(command)) {
    kind = AiDocumentKind.proforma;
  } else if (RegExp(r'\b(?:quotation|quote|nukuu)\b').hasMatch(command)) {
    kind = AiDocumentKind.quotation;
  } else if (RegExp(r'\b(?:receipt|risiti)\b').hasMatch(command)) {
    kind = AiDocumentKind.receipt;
  } else if (RegExp(r'\b(?:invoice|ankara)\b').hasMatch(command)) {
    kind = AiDocumentKind.invoice;
  } else {
    return null;
  }
  if (!RegExp(
    r'^(?:niandalie|niandae|nitengenezee|tengeneza|andaa|create|prepare|make)\s+(?:invoice|ankara|quotation|quote|nukuu|proforma(?: invoice)?|advance(?: payment)?(?: invoice)?|receipt|risiti)$',
  ).hasMatch(command)) {
    throw const FormatException('unsupported-command');
  }
  final fields = <String, String>{};
  const aliases = {
    'mteja': 'customer',
    'customer': 'customer',
    'client': 'customer',
    'bidhaa': 'description',
    'huduma': 'description',
    'item': 'description',
    'description': 'description',
    'idadi': 'quantity',
    'quantity': 'quantity',
    'bei': 'unitPrice',
    'price': 'unitPrice',
    'unit price': 'unitPrice',
    'subtotal': 'subtotal',
    'tax': 'tax',
    'kodi': 'tax',
    'advance': 'advancePaid',
    'malipo ya awali': 'advancePaid',
  };
  for (final section in sections.skip(1)) {
    final colon = section.indexOf(':');
    if (colon < 1) throw const FormatException('invalid-field');
    final key = aliases[section.substring(0, colon).trim().toLowerCase()];
    final value = section.substring(colon + 1).trim();
    if (key == null || value.isEmpty || fields.containsKey(key)) {
      throw const FormatException('invalid-field');
    }
    fields[key] = value;
  }
  final allowed = kind == AiDocumentKind.advance
      ? {'customer', 'subtotal', 'tax', 'advancePaid'}
      : {
          'customer',
          'description',
          'quantity',
          'unitPrice',
          if (kind == AiDocumentKind.receipt) 'tax',
        };
  if (fields.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('unsupported-field');
  }
  final itemFields = ['description', 'quantity', 'unitPrice'];
  final providedItems = itemFields.where(fields.containsKey).length;
  if (providedItems != 0 && providedItems != itemFields.length) {
    throw const FormatException('incomplete-item');
  }
  double? number(String key, {bool allowZero = false}) {
    final raw = fields[key];
    if (raw == null) return null;
    if (!RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$').hasMatch(raw)) {
      throw const FormatException('invalid-number');
    }
    final parsed = double.tryParse(raw.replaceAll(',', ''));
    if (parsed == null ||
        !parsed.isFinite ||
        parsed > 1000000000000 ||
        (allowZero ? parsed < 0 : parsed <= 0)) {
      throw const FormatException('invalid-number');
    }
    return parsed;
  }

  final quantity = number('quantity');
  if (kind == AiDocumentKind.receipt &&
      quantity != null &&
      quantity != quantity.roundToDouble()) {
    throw const FormatException('invalid-quantity');
  }
  return AiDocumentDraft(
    kind: kind,
    customer: fields['customer'],
    description: fields['description'],
    quantity: quantity,
    unitPrice: number('unitPrice'),
    subtotal: number('subtotal', allowZero: true),
    tax: number('tax', allowZero: true),
    advancePaid: number('advancePaid', allowZero: true),
    requestedAmount: requestedAmount,
  );
}
