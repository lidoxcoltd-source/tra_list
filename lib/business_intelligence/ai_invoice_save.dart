import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tra_list/business_intelligence/ai_document_draft.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/document_terms_service.dart';
import 'package:tra_list/services/notification_service.dart';
import 'package:tra_list/stock/stock_models.dart';
import 'package:tra_list/stock/stock_service.dart';

class AiInvoiceSave {
  AiInvoiceSave(this.businessId, this.isCurrent);

  final String businessId;
  final bool Function() isCurrent;
  DocumentReference<Map<String, dynamic>>? _ref;
  Map<String, dynamic>? _data;
  String? _uid;

  void _checkAccess() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null ||
        (_uid != null && user.uid != _uid) ||
        !isCurrent() ||
        !BusinessAccessService.hasBusinessAccess ||
        BusinessAccessService.businessId != businessId ||
        !BusinessAccessService.can('invoices', 'create') ||
        !BusinessAccessService.can('invoices', 'view')) {
      throw StateError('Invoice access changed');
    }
  }

  Future<String> save(AiDocumentDraft draft) async {
    _checkAccess();
    final db = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser!;
    _uid ??= user.uid;
    _ref ??= db
        .collection('users')
        .doc(businessId)
        .collection('invoices')
        .doc();
    final ref = _ref!;
    if (_data == null) {
      final profile = await db
          .collection('users')
          .doc(businessId)
          .collection('profile')
          .doc('company')
          .get(const GetOptions(source: Source.server));
      _checkAccess();
      if (!profile.exists) throw StateError('Business profile not found');
      final profileData = profile.data()!;
      final company = <String, dynamic>{
        for (final key in const [
          'name',
          'shopNickname',
          'ownerName',
          'address',
          'phone',
          'email',
          'website',
          'taxId',
          'role',
          'handle',
          'logoUrl',
          'logoSource',
          'language',
          'beneficiary',
          'bank',
          'account',
          'swift',
          'paymentMethod',
          'colors',
          'documentDesigns',
        ])
          if (profileData.containsKey(key)) key: profileData[key],
      };
      final now = DateTime.now();
      String date(DateTime value) =>
          '${value.day}/${value.month}/${value.year}';
      final number = draft.invoiceNumber ?? 'INV-${ref.id}';
      final terms = DocumentTermsService.selectedFor(profileData, 'invoice');
      final items = [
        for (final item in draft.invoiceItems)
          {
            'description': item.description,
            'qty': item.quantity,
            'unit': item.unitPrice,
            'amount': item.quantity * item.unitPrice,
            if (item.productId != null) 'productId': item.productId,
          },
      ];
      _data = {
        'company': company,
        'client': {'name': draft.customer},
        'documentTerms': {
          ...terms,
          'includeConditions': draft.terms != null,
          'conditions': draft.terms ?? '',
        },
        'invoice': {
          'number': number,
          'name': draft.invoiceName ?? '',
          'issueDate': date(draft.issueDate ?? now),
          'dueDate': date(draft.dueDate ?? now),
          'paymentMethod': company['paymentMethod'],
        },
        'items': items,
        'total': draft.invoiceItems.fold<double>(
          0,
          (total, item) => total + item.quantity * item.unitPrice,
        ),
        'kind': 'invoice',
        'id': ref.id,
        'uid': user.uid,
        'aiInvoiceRequestId': ref.id,
      };
    }
    _checkAccess();
    final data = _data!;
    final existing = await ref.get(const GetOptions(source: Source.server));
    _checkAccess();
    if (existing.exists) {
      if (existing.get('aiInvoiceRequestId') != ref.id ||
          existing.get('uid') != _uid) {
        throw StateError('Invoice identifier conflict');
      }
      return ref.id;
    }
    final lines = [
      for (final item in draft.invoiceItems)
        if (item.productId != null)
          SaleLine(productId: item.productId!, quantity: item.quantity),
    ];
    final saleData = {...data, 'createdAt': FieldValue.serverTimestamp()};
    if (lines.isNotEmpty) {
      await StockService.current().finalizeSale(
        saleRef: ref,
        saleData: saleData,
        lines: lines,
        requireTracked: true,
      );
    } else {
      await db.runTransaction((tx) async {
        final previous = await tx.get(ref);
        if (previous.exists) {
          if (previous.get('aiInvoiceRequestId') != ref.id ||
              previous.get('uid') != _uid) {
            throw StateError('Invoice identifier conflict');
          }
          return;
        }
        tx.set(ref, saleData);
      });
    }
    _checkAccess();
    final saved = await ref.get(const GetOptions(source: Source.server));
    _checkAccess();
    if (!saved.exists ||
        saved.get('aiInvoiceRequestId') != ref.id ||
        saved.get('uid') != _uid) {
      throw StateError('Invoice save could not be verified');
    }
    await NotificationService.notifyOwner(
      action: 'invoice',
      summary: 'created invoice ${(data['invoice'] as Map)['number']}',
      amount: data['total'] as double,
    );
    return ref.id;
  }
}
