import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tra_list/ReceiptPage.dart';
import 'package:tra_list/LocalStorageService.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/QRCodeService.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ReceiptViewController extends GetxController {
  final isLoading = true.obs;
  final errorMessage = ''.obs;
  final receiptData = Rxn<ReceiptData>();

  @override
  void onInit() {
    super.onInit();
    loadReceipt();
  }

  void loadReceipt() async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      final receiptId = Get.parameters['id'];
      if (receiptId == null || receiptId.isEmpty) {
        errorMessage.value = 'Receipt ID not provided';
        return;
      }

      print('Loading receipt with ID: $receiptId');

      // Try to load from Firestore first
      ReceiptData? receipt = await _loadFromFirestore(receiptId);

      // If not found in Firestore, try local storage
      receipt ??= await _loadFromLocalStorage(receiptId);

      if (receipt != null) {
        receiptData.value = receipt;
      } else {
        errorMessage.value = 'Receipt not found';
      }
    } catch (e) {
      print('Error loading receipt: $e');
      errorMessage.value = 'Error loading receipt: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<ReceiptData?> _loadFromFirestore(String receiptId) async {
    try {
      print('Trying to load from Firestore...');

      final doc = await FirebaseFirestore.instance
          .collection('receipts')
          .doc(receiptId)
          .get()
          .timeout(const Duration(seconds: 5));

      if (doc.exists) {
        print('Found receipt in Firestore');
        final data = doc.data() as Map<String, dynamic>;
        return _mapToReceiptData(data);
      }
    } catch (e) {
      print('Failed to load from Firestore: $e');
    }

    // POS invoices are scoped under their business instead of /receipts.
    final businessId =
        (Get.parameters['businessId'] ?? BusinessAccessService.businessId)
            .trim();
    if (businessId.isNotEmpty) {
      try {
        final invoice = await FirebaseFirestore.instance
            .collection('users')
            .doc(businessId)
            .collection('invoices')
            .doc(receiptId)
            .get()
            .timeout(const Duration(seconds: 5));
        if (invoice.exists) return _mapPosInvoiceToReceipt(invoice.data()!);
      } catch (e) {
        print('Failed to load POS invoice from Firestore: $e');
      }
    }
    return null;
  }

  ReceiptData _mapPosInvoiceToReceipt(Map<String, dynamic> data) {
    Map<String, dynamic> map(Object? value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

    final company = map(data['company']);
    final client = map(data['client']);
    final invoice = map(data['invoice']);
    final total = (data['total'] as num?)?.toDouble() ?? 0;
    final items = (data['items'] as List? ?? const []).whereType<Map>().map((
      raw,
    ) {
      final item = Map<String, dynamic>.from(raw);
      return LineItem(
        description: (item['description'] ?? item['name'] ?? '').toString(),
        qty: (item['qty'] as num?)?.round() ?? 1,
        amount: (item['amount'] as num?)?.toDouble() ?? 0,
      );
    }).toList();

    return ReceiptData(
      company: CompanyInfo(
        name: (company['name'] ?? '').toString(),
        addressLine: (company['addressLine'] ?? company['address'] ?? '')
            .toString(),
        mobile: (company['mobile'] ?? company['phone'] ?? '').toString(),
        tin: (company['tin'] ?? '').toString(),
        vrn: (company['vrn'] ?? '').toString(),
        serialNo: (company['serialNo'] ?? '').toString(),
        uim: (company['uim'] ?? '').toString(),
        taxOffice: (company['taxOffice'] ?? '').toString(),
        businessType: (company['businessType'] ?? '').toString(),
        businessDescription: (company['businessDescription'] ?? '').toString(),
        shopNickname: (company['shopNickname'] ?? '').toString(),
        email: (company['email'] ?? '').toString(),
        website: (company['website'] ?? '').toString(),
        facebookUrl: (company['facebookUrl'] ?? '').toString(),
        instagramUrl: (company['instagramUrl'] ?? '').toString(),
        tiktokUrl: (company['tiktokUrl'] ?? '').toString(),
        socialHandle: (company['handle'] ?? '').toString(),
        logoUrl: (company['logoUrl'] ?? '').toString(),
      ),
      customer: CustomerInfo(
        name: (client['name'] ?? '').toString(),
        idType: '',
        idNo: '',
        mobile: '',
        vrn: '',
      ),
      meta: ReceiptMeta(
        receiptNo: (invoice['number'] ?? data['id'] ?? '').toString(),
        zNumber: '',
        receiptDate: (invoice['issueDate'] ?? '').toString(),
        receiptTime: '',
      ),
      items: items,
      totalExclTax: total,
      tax: 0,
      totalInclTax: total,
      verificationCode: (data['id'] ?? invoice['number'] ?? '').toString(),
      servedBy: (data['cashierName'] ?? '').toString(),
    );
  }

  Future<ReceiptData?> _loadFromLocalStorage(String receiptId) async {
    try {
      print('Trying to load from local storage...');

      final data = LocalStorageService.getReceiptByCode(receiptId);
      if (data != null && data.isNotEmpty) {
        print('Found receipt in local storage');
        return _mapToReceiptData(data);
      }
    } catch (e) {
      print('Failed to load from local storage: $e');
    }
    return null;
  }

  ReceiptData _mapToReceiptData(Map<String, dynamic> data) {
    final company = data['company'] as Map<String, dynamic>? ?? {};
    final customer = data['customer'] as Map<String, dynamic>? ?? {};
    final meta = data['meta'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List<dynamic>? ?? [];

    return ReceiptData(
      company: CompanyInfo(
        name: company['name'] ?? '',
        addressLine: company['addressLine'] ?? '',
        mobile: company['mobile'] ?? '',
        tin: company['tin'] ?? '',
        vrn: company['vrn'] ?? '',
        serialNo: company['serialNo'] ?? '',
        uim: company['uim'] ?? '',
        taxOffice: company['taxOffice'] ?? '',
        logo: const AssetImage('assets/tra-logo.png'),
        businessType: company['businessType']?.toString() ?? '',
        businessDescription: company['businessDescription']?.toString() ?? '',
        shopNickname: company['shopNickname']?.toString() ?? '',
        email: company['email']?.toString() ?? '',
        website: company['website']?.toString() ?? '',
        facebookUrl: company['facebookUrl']?.toString() ?? '',
        instagramUrl: company['instagramUrl']?.toString() ?? '',
        tiktokUrl: company['tiktokUrl']?.toString() ?? '',
        socialHandle: company['handle']?.toString() ?? '',
        logoUrl: company['logoUrl']?.toString() ?? '',
      ),
      customer: CustomerInfo(
        name: customer['name'] ?? '',
        idType: customer['idType'] ?? '',
        idNo: customer['idNo'] ?? '',
        mobile: customer['mobile'] ?? '',
        vrn: customer['vrn'] ?? '',
      ),
      meta: ReceiptMeta(
        receiptNo: meta['receiptNo'] ?? '',
        zNumber: meta['zNumber'] ?? '',
        receiptDate: meta['receiptDate'] ?? '',
        receiptTime: meta['receiptTime'] ?? '',
      ),
      items: items.map((item) {
        final itemMap = item as Map<String, dynamic>;
        return LineItem(
          description: itemMap['description'] ?? '',
          qty: itemMap['qty'] ?? 1,
          amount: (itemMap['amount'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList(),
      totalExclTax: (data['totalExclTax'] as num?)?.toDouble() ?? 0.0,
      tax: (data['tax'] as num?)?.toDouble() ?? 0.0,
      totalInclTax: (data['totalInclTax'] as num?)?.toDouble() ?? 0.0,
      verificationCode: data['verificationCode'] ?? '',
      qr: const AssetImage('assets/frame.png'),
      servedBy: (data['cashierName'] ?? data['servedBy'] ?? '').toString(),
    );
  }

  void shareReceiptUrl() {
    final receiptId = Get.parameters['id'];
    if (receiptId != null) {
      final url = Get.currentRoute;
      Get.snackbar(
        'Share Receipt',
        'Receipt URL: $url',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
    }
  }

  void copyReceiptUrl() {
    final receiptId = Get.parameters['id'];
    if (receiptId != null) {
      final url =
          '${Uri.base.scheme}://${Uri.base.host}:${Uri.base.port}${Get.currentRoute}';
      print('Receipt URL: $url'); // In a real app, you'd use clipboard package
      Get.snackbar(
        'URL Copied',
        'Receipt URL: $url',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    }
  }
}

class ReceiptViewPage extends StatelessWidget {
  ReceiptViewPage({super.key});

  final controller = Get.put(ReceiptViewController());

  void _showQRDialog(BuildContext context, String receiptId) {
    final receiptUrl = QRCodeService.getCurrentReceiptUrl();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receipt QR Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QRCodeService.generateReceiptQR(receiptId: receiptId, size: 350),
            const SizedBox(height: 16),
            const Text(
              'Scan to view receipt online',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SelectableText(
              receiptUrl,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              controller.copyReceiptUrl();
              Navigator.of(context).pop();
            },
            child: const Text('Copy URL'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).canPop()
              ? Get.back()
              : Get.offAllNamed('/'),
        ),
        title: const Text('Receipt verification'),
        backgroundColor: const Color(0xFF081525),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // QR Code button
          IconButton(
            onPressed: () {
              final receiptId = Get.parameters['id'];
              if (receiptId != null && receiptId.isNotEmpty) {
                _showQRDialog(context, receiptId);
              }
            },
            icon: const Icon(Icons.qr_code),
            tooltip: 'Show QR Code',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'share':
                  controller.shareReceiptUrl();
                  break;
                case 'copy':
                  controller.copyReceiptUrl();
                  break;
                case 'qr':
                  final receiptId = Get.parameters['id'];
                  if (receiptId != null && receiptId.isNotEmpty) {
                    _showQRDialog(context, receiptId);
                  }
                  break;
                case 'reload':
                  controller.loadReceipt();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'qr',
                child: Row(
                  children: [
                    Icon(Icons.qr_code),
                    SizedBox(width: 8),
                    Text('Show QR Code'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share),
                    SizedBox(width: 8),
                    Text('Share URL'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy),
                    SizedBox(width: 8),
                    Text('Copy URL'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'reload',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('Reload'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading receipt...'),
              ],
            ),
          );
        }

        if (controller.errorMessage.value.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Receipt Not Found',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.red.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.errorMessage.value,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: controller.loadReceipt,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: () => Get.offAllNamed('/'),
                        icon: const Icon(Icons.home),
                        label: const Text('Go Home'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        if (controller.receiptData.value != null) {
          return _PublicReceiptVerificationView(
            data: controller.receiptData.value!,
          );
        }

        return const Center(child: Text('No receipt data available'));
      }),
    );
  }
}

class _PublicReceiptVerificationView extends StatelessWidget {
  const _PublicReceiptVerificationView({required this.data});

  final ReceiptData data;

  bool get _isSwahili => Get.locale?.languageCode == 'sw';

  String _money(num value) => NumberFormat('#,##0.00').format(value);

  Uri? _webUri(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  Uri? _whatsAppUri(String phone) {
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0') && digits.length == 10) {
      digits = '255${digits.substring(1)}';
    }
    if (digits.length < 8 || digits.length > 15) return null;
    return Uri.https('wa.me', '/$digits');
  }

  Future<void> _openLink(BuildContext context, Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open this business link.');
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF101F32),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFF29435C)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x3000D7C2),
          blurRadius: 28,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );

  Widget _labelValue(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF9FB2C5), fontSize: 13),
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sw = _isSwahili;
    final company = data.company;
    final businessName = company.shopNickname.trim().isNotEmpty
        ? company.shopNickname.trim()
        : company.name.trim();
    final links = <_BusinessLink>[];
    void addLink(String label, IconData icon, Uri? uri) {
      if (uri != null) links.add(_BusinessLink(label, icon, uri));
    }

    addLink('WhatsApp', Icons.chat_rounded, _whatsAppUri(company.mobile));
    addLink(
      sw ? 'Tovuti' : 'Website',
      Icons.language_rounded,
      _webUri(company.website),
    );
    addLink('Facebook', Icons.public_rounded, _webUri(company.facebookUrl));
    addLink(
      'Instagram',
      Icons.camera_alt_rounded,
      _webUri(company.instagramUrl),
    );
    addLink('TikTok', Icons.music_note_rounded, _webUri(company.tiktokUrl));
    addLink(
      sw ? 'Mitandao' : 'Social',
      Icons.alternate_email_rounded,
      _webUri(company.socialHandle),
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF07111F), Color(0xFF0A2030), Color(0xFF07111F)],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 36),
            children: [
              _card(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E9D82).withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: const Color(0xFF2BE0B4).withValues(alpha: .4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            color: Color(0xFF43E0B6),
                            size: 19,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            sw ? 'RISITI IMETHIBITISHWA' : 'RECEIPT VERIFIED',
                            style: const TextStyle(
                              color: Color(0xFF70F1CD),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      sw ? 'Uthibitisho wa risiti' : 'Receipt verification',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sw
                          ? 'Taarifa za risiti hii zimepatikana kwenye rekodi za biashara.'
                          : 'This receipt matches a record from the business.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFB0C1D0),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'TZS ${_money(data.totalInclTax)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF55E6C1),
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${sw ? 'Risiti' : 'Receipt'} ${data.meta.receiptNo}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFD4E0E9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      sw ? 'Muhtasari wa mauzo' : 'Sale summary',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _labelValue(
                      sw ? 'Tarehe' : 'Date',
                      '${data.meta.receiptDate} ${data.meta.receiptTime}'
                          .trim(),
                    ),
                    _labelValue(
                      sw ? 'Namba ya uthibitisho' : 'Verification code',
                      data.verificationCode,
                    ),
                    const Divider(color: Color(0xFF29435C), height: 22),
                    for (final item in data.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item.description}  ×${item.qty}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'TZS ${_money(item.amount)}',
                              style: const TextStyle(
                                color: Color(0xFFD5E1EA),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(color: Color(0xFF29435C), height: 22),
                    _labelValue(
                      sw ? 'Jumla' : 'Total',
                      'TZS ${_money(data.totalInclTax)}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _businessLogo(company.logoUrl),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sw ? 'Kuhusu biashara' : 'About the business',
                                style: const TextStyle(
                                  color: Color(0xFF58E4C0),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                businessName.isEmpty
                                    ? (sw ? 'Biashara' : 'Business')
                                    : businessName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (company.businessType.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        company.businessType,
                        style: const TextStyle(
                          color: Color(0xFFB0C1D0),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (company.businessDescription.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        company.businessDescription,
                        style: const TextStyle(
                          color: Color(0xFFD0DCE6),
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (company.addressLine.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _labelValue(
                        sw ? 'Anwani' : 'Address',
                        company.addressLine,
                      ),
                    ],
                    if (company.mobile.isNotEmpty)
                      _labelValue(sw ? 'Simu' : 'Phone', company.mobile),
                    if (company.email.isNotEmpty)
                      _labelValue('Email', company.email),
                    if (company.website.isNotEmpty)
                      _labelValue(sw ? 'Tovuti' : 'Website', company.website),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (links.isNotEmpty) ...[
                Text(
                  sw ? 'Wasiliana na biashara' : 'Connect with the business',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFDDE7EF),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final link in links)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF74E9CF),
                          side: const BorderSide(color: Color(0xFF34766F)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                        ),
                        onPressed: () => _openLink(context, link.uri),
                        icon: Icon(link.icon, size: 18),
                        label: Text(link.label),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 26),
              Text(
                sw
                    ? 'Ukurasa huu wa umma unaonyesha uthibitisho wa risiti na taarifa zilizowekwa na biashara.'
                    : 'This public page verifies the receipt and displays business-provided information.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8DA2B4),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'MJASI  •  VERIFIED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF56DABD),
                  letterSpacing: 1.5,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _businessLogo(String logoUrl) {
    final uri = _webUri(logoUrl);
    if (uri == null) {
      return Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: const Color(0xFF18364A),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(
          Icons.storefront_rounded,
          color: Color(0xFF61E6C6),
          size: 28,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.network(
        uri.toString(),
        width: 58,
        height: 58,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.storefront_rounded,
          color: Color(0xFF61E6C6),
          size: 28,
        ),
      ),
    );
  }
}

class _BusinessLink {
  const _BusinessLink(this.label, this.icon, this.uri);

  final String label;
  final IconData icon;
  final Uri uri;
}
