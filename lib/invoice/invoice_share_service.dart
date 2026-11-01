import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:tra_list/services/pdf/advance_payment_pdf.dart';
import 'package:tra_list/services/pdf/delivery_note_pdf.dart';
import 'package:tra_list/services/pdf/invoice_pdf.dart';
import 'package:tra_list/services/pdf/payment_details_pdf.dart';
import 'package:tra_list/services/pdf/payment_reminder_pdf.dart';
import 'package:tra_list/services/pdf/proforma_pdf.dart';
import 'package:tra_list/services/pdf/quotation_pdf.dart';
import 'package:tra_list/services/document_design_service.dart';
import 'package:tra_list/services/profile_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SharedInvoiceLink {
  const SharedInvoiceLink({required this.token, required this.url});

  final String token;
  final String url;
}

class InvoiceShareService {
  InvoiceShareService._();

  static final _firestore = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;
  static const _hostedAppUrl = 'https://mjasipos.web.app/';

  static String createPublicUrl(String token) {
    final base = Uri.base;
    if (base.scheme == 'https' || base.scheme == 'http') {
      return base
          .replace(path: '/', query: null, fragment: '/shared-document/$token')
          .toString();
    }
    return '$_hostedAppUrl#/shared-document/$token';
  }

  static String normalizeWhatsAppNumber(String value) {
    var digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0')) {
      digits = '255${digits.substring(1)}';
    } else if (digits.length == 9) {
      digits = '255$digits';
    }
    if (digits.length < 8 || digits.length > 15) {
      throw const FormatException(
        'Enter a valid phone number with its country code.',
      );
    }
    return digits;
  }

  static Future<SharedInvoiceLink> createLink({
    required String businessUid,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    final token = _newToken();
    final kind = (data['kind']?.toString() ?? 'invoice');
    final company = Map<String, dynamic>.from(data['company'] as Map? ?? {});
    final candidateLogoUrl =
        (company['logoUrl'] ?? company['logoURL'] ?? company['logo'])
            ?.toString()
            .trim() ??
        '';
    final candidateLogoUri = Uri.tryParse(candidateLogoUrl);
    final hasPublicLogoUrl =
        candidateLogoUri?.scheme == 'https' &&
        (candidateLogoUri?.host.isNotEmpty ?? false);
    late final Map<String, dynamic> publicDataSource;
    if (hasPublicLogoUrl) {
      publicDataSource = {
        ...data,
        'company': {...company, 'logoUrl': candidateLogoUrl},
      };
    } else {
      final profile = await ProfileService.loadOrCreate();
      publicDataSource = {
        ...data,
        'company': {
          ...profile,
          ...company,
          'logoUrl': profile['logoUrl'] ?? '',
          'logoSource': profile['logoSource'] ?? 'firebase',
        },
      };
    }
    final publicData = _publicSnapshot(publicDataSource, kind);
    final publicRef = _firestore.collection('sharedDocuments').doc(token);
    await publicRef.set({
      'businessUid': businessUid,
      'sourceDocumentId': documentId,
      'module': kind == 'quotation' ? 'quotations' : 'invoices',
      'kind': kind,
      'document': publicData,
      'active': true,
      'expiresAt': null,
      'downloadUrl': '',
      'createdAt': FieldValue.serverTimestamp(),
    });

    return SharedInvoiceLink(token: token, url: createPublicUrl(token));
  }

  static Future<Uint8List> generatePdfBytes(
    Map<String, dynamic> data,
    String kind,
  ) => _generatePdf(data, kind);

  static String fileName(String kind, Map<String, dynamic> data) =>
      _fileName(kind, data);

  static Future<bool> openWhatsApp({
    required String businessUid,
    required String documentId,
    required String token,
    required String module,
    required String kind,
    required String documentNumber,
    required String clientName,
    required num total,
    required String recipientName,
    required String recipientPhone,
  }) async {
    final phone = normalizeWhatsAppNumber(recipientPhone);
    final history = await _firestore
        .collection('users')
        .doc(businessUid)
        .collection('documentShares')
        .add({
          'businessUid': businessUid,
          'shareToken': token,
          'sourceDocumentId': documentId,
          'module': module,
          'kind': kind,
          'documentNumber': documentNumber,
          'clientName': clientName,
          'total': total,
          'recipientName': recipientName.trim(),
          'recipientPhone': phone,
          'channel': 'whatsapp',
          'status': 'link_ready',
          'linkRevoked': false,
          'sharedAt': FieldValue.serverTimestamp(),
        });

    final message = [
      'Hello${recipientName.trim().isEmpty ? '' : ' ${recipientName.trim()}'},',
      'Here is ${_documentLabel(kind)} ${documentNumber.isEmpty ? '' : '#$documentNumber'}',
      if (total > 0) 'Total: TSH ${_money(total)}',
      createPublicUrl(token),
    ].join('\n');
    final whatsappUris = [
      Uri.https('wa.me', '/$phone', {'text': message}),
      Uri.https('api.whatsapp.com', '/send', {'phone': phone, 'text': message}),
    ];
    var opened = false;
    Object? launchError;
    for (final uri in whatsappUris) {
      try {
        opened = await launchUrl(
          uri,
          mode: kIsWeb
              ? LaunchMode.platformDefault
              : LaunchMode.externalApplication,
        );
        if (opened) break;
      } catch (error) {
        launchError = error;
        debugPrint('Could not launch WhatsApp URL $uri: $error');
      }
    }
    if (opened) {
      await history.update({'status': 'whatsapp_opened'});
    } else if (launchError != null) {
      debugPrint('WhatsApp could not be opened using either supported URL.');
    }
    return opened;
  }

  static Future<void> revoke({
    required String businessUid,
    required String token,
  }) async {
    final publicRef = _firestore.collection('sharedDocuments').doc(token);
    final snapshot = await publicRef.get();
    if (!snapshot.exists) {
      throw StateError('This customer link is already revoked or unavailable.');
    }
    if ((snapshot.data()?['downloadUrl'] ?? '').toString().isNotEmpty) {
      try {
        await _storage.ref('sharedDocuments/$token/document.pdf').delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
    }
    await publicRef.delete();

    final history = await _firestore
        .collection('users')
        .doc(businessUid)
        .collection('documentShares')
        .where('shareToken', isEqualTo: token)
        .get();
    final batch = _firestore.batch();
    for (final share in history.docs) {
      batch.update(share.reference, {'linkRevoked': true});
    }
    await batch.commit();
  }

  static Future<Uint8List> _generatePdf(
    Map<String, dynamic> data,
    String kind,
  ) async {
    switch (kind) {
      case 'quotation':
        return QuotationPdf.generateBytes(data);
      case 'proforma':
        return ProformaPdf.generateBytes(data);
      case 'delivery':
        return DeliveryNotePdf.generateBytes(data);
      case 'advance_payment':
      case 'advance':
        return AdvancePaymentPdf.generateBytes(data);
      case 'reminder':
        return PaymentReminderPdf.generateBytes(data);
      case 'payment_details':
        return PaymentDetailsPdf.generateBytes(data);
      default:
        return InvoicePdf.generateBytes(data);
    }
  }

  static Map<String, dynamic> _publicSnapshot(
    Map<String, dynamic> data,
    String kind,
  ) {
    final company = data['company'] as Map? ?? const {};
    final client = data['client'] as Map? ?? const {};
    final invoice = data['invoice'] as Map? ?? const {};
    final terms = data['documentTerms'] as Map? ?? const {};
    final items = data['items'] as List? ?? const [];
    final companyKeys = [
      'name',
      'address',
      'email',
      'phone',
      'website',
      'taxId',
      'beneficiary',
      'bank',
      'account',
      'swift',
      'paymentMethod',
      'logoUrl',
      'logoSource',
      'colors',
      'handle',
    ];
    final invoiceKeys = [
      'number',
      'numberCode',
      'name',
      'issueDate',
      'dueDate',
      'paymentMethod',
    ];
    final publicCompany = {
      for (final key in companyKeys)
        if (company.containsKey(key)) key: company[key],
    };
    if (publicCompany.isEmpty) publicCompany['name'] = 'Business document';
    return {
      'company': publicCompany,
      'client': {'name': (client['name'] ?? '').toString()},
      'invoice': {
        for (final key in invoiceKeys)
          if (invoice.containsKey(key)) key: invoice[key],
      },
      'items': [
        for (final raw in items.whereType<Map>())
          {
            'description': (raw['description'] ?? '').toString(),
            'qty': raw['qty'] is num ? raw['qty'] : 1,
            'unit': raw['unit'] is num ? raw['unit'] : 0,
            'amount': raw['amount'] is num ? raw['amount'] : 0,
          },
      ],
      'total': data['total'] is num ? data['total'] : 0,
      if (data['subtotal'] is num) 'subtotal': data['subtotal'],
      if (data['tax'] is num) 'tax': data['tax'],
      if (data['advancePaid'] is num) 'advancePaid': data['advancePaid'],
      'documentTerms': {
        if (terms['includeConditions'] != false &&
            (terms['conditions']?.toString().trim().isNotEmpty ?? false))
          'conditions': terms['conditions'].toString(),
        if (terms['note']?.toString().trim().isNotEmpty ?? false)
          'note': terms['note'].toString(),
        if (terms['delivery']?.toString().trim().isNotEmpty ?? false)
          'delivery': terms['delivery'].toString(),
      },
      'documentDesign':
          (data['documentDesign'] as Map?)?.cast<String, dynamic>() ??
          DocumentDesignService.selectedFor(
            company.cast<String, dynamic>(),
            _designType(kind),
          ),
    };
  }

  static String _designType(String kind) => switch (kind) {
    'delivery' => 'delivery_note',
    'advance' => 'advance_payment',
    'proforma' => 'proforma',
    'quotation' => 'quotation',
    _ => 'invoice',
  };

  static String _newToken() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _fileName(String kind, Map<String, dynamic> data) {
    final invoice = data['invoice'] as Map? ?? const {};
    final number = (invoice['number'] ?? 'document').toString();
    return '${kind}_$number.pdf'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
  }

  static String _documentLabel(String kind) => switch (kind) {
    'quotation' => 'quotation',
    'proforma' => 'proforma invoice',
    'delivery' => 'delivery note',
    'advance_payment' || 'advance' => 'advance payment document',
    'reminder' => 'payment reminder',
    'payment_details' => 'payment details',
    _ => 'invoice',
  };

  static String _money(num value) => value
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}
