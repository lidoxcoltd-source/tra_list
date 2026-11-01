import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:tra_list/services/pdf/delivery_note_pdf.dart';
import 'package:tra_list/services/pdf/invoice_pdf.dart';
import 'package:tra_list/services/pdf/payment_reminder_pdf.dart';
import 'package:tra_list/services/pdf/proforma_pdf.dart';
import 'package:tra_list/services/pdf/advance_payment_pdf.dart';
import 'package:tra_list/services/pdf/quotation_pdf.dart';
import 'package:tra_list/services/pages/document_design_page.dart';
import 'package:tra_list/services/pages/document_terms_page.dart';
import 'package:tra_list/invoice/document_share_sheet.dart';
import 'package:tra_list/invoice/document_shares_page.dart';
import 'package:tra_list/theme/app_theme.dart';

import 'InvoicePage.dart' as invoice_page;
import 'advance_invoice_page.dart';
import 'quotation_page.dart';
import 'package:tra_list/services/business_access_service.dart';
import 'package:tra_list/services/notification_service.dart';
import 'package:tra_list/stock/stock_service.dart';
import 'package:tra_list/stock/stock_ui.dart';

String _deletedSummary(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data() ?? const <String, dynamic>{};
  final kind = (data['kind'] ?? 'invoice').toString();
  final invoice = data['invoice'];
  final number = invoice is Map ? (invoice['number'] ?? '').toString() : '';
  final total = (data['total'] as num?)?.toDouble();
  return 'deleted $kind $number${total == null ? '' : ' (TSH ${total.toStringAsFixed(0)})'}'
      .replaceAll('  ', ' ');
}

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  final _searchC = TextEditingController();
  String _query = '';
  static const _pageSize = 30;
  Query<Map<String, dynamic>>? _documentsQuery;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _documentsStream;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _olderDocuments = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDocument;
  bool _hasMoreDocuments = true;
  bool _loadingMoreDocuments = false;

  @override
  void initState() {
    super.initState();
    if (FirebaseAuth.instance.currentUser != null) _initializeDocumentsQuery();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  void _initializeDocumentsQuery() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('users')
        .doc(BusinessAccessService.businessId)
        .collection('invoices');
    final canViewInvoices = BusinessAccessService.can('invoices', 'view');
    final canViewQuotations = BusinessAccessService.can('quotations', 'view');
    if (canViewInvoices && !canViewQuotations) {
      query = query.where('kind', isNotEqualTo: 'quotation');
    } else if (!canViewInvoices && canViewQuotations) {
      query = query.where('kind', isEqualTo: 'quotation');
    }
    _documentsQuery = query.orderBy('createdAt', descending: true);
    _documentsStream = _documentsQuery!.limit(_pageSize).snapshots();
  }

  Future<void> _loadMoreDocuments() async {
    final query = _documentsQuery;
    final cursor = _lastDocument;
    if (_loadingMoreDocuments ||
        !_hasMoreDocuments ||
        query == null ||
        cursor == null) {
      return;
    }
    setState(() => _loadingMoreDocuments = true);
    try {
      final page = await query
          .startAfterDocument(cursor)
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      setState(() {
        _olderDocuments.addAll(page.docs);
        _hasMoreDocuments = page.docs.length == _pageSize;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load more documents: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        Get.snackbar('error'.tr, 'Could not load more documents.');
      }
    } finally {
      if (mounted) setState(() => _loadingMoreDocuments = false);
    }
  }

  Future<void> _refreshDocuments() async {
    final query = _documentsQuery;
    if (query == null) return;
    setState(() {
      _olderDocuments.clear();
      _lastDocument = null;
      _hasMoreDocuments = true;
      _documentsStream = query.limit(_pageSize).snapshots();
    });
  }

  final Color primary = MjasiColors.primaryBlue;
  final Color primaryDark = MjasiColors.primaryNavy;
  final Color bgColor = MjasiColors.background;
  final Color surfaceColor = MjasiColors.surface;
  final Color textMain = MjasiColors.textPrimary;
  final Color textMuted = MjasiColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final screenWidth = MediaQuery.sizeOf(context).width;

    if (user == null) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text(
            'My Documents',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          elevation: 0,
          foregroundColor: Colors.white,
          centerTitle: true,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryDark, primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        body: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_outline, size: 48, color: primary),
                ),
                const SizedBox(height: 24),
                Text(
                  'Authentication Required',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textMain,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please sign in to view and manage your documents safely.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textMuted),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.login),
                    onPressed: () async {
                      await FirebaseAuth.instance.signInAnonymously();
                      Get.snackbar(
                        'Signed in',
                        'Anonymous sign-in complete',
                        backgroundColor: Colors.green,
                        colorText: Colors.white,
                      );
                    },
                    label: const Text(
                      'Sign In Anonymously',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      floatingActionButton:
          screenWidth < 700 && BusinessAccessService.can('invoices', 'create')
          ? FloatingActionButton.extended(
              elevation: 4,
              highlightElevation: 8,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const invoice_page.InvoicePage(),
                  ),
                );
              },
              label: const Text(
                'New Document',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              icon: const Icon(Icons.add_circle_outline),
              backgroundColor: primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _documentsStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: primary));
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.shade400,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Something went wrong',
                    style: TextStyle(
                      color: textMain,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snap.error}',
                    style: TextStyle(color: textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final firstPage = snap.data?.docs ?? [];
          if (snap.hasData) {
            _lastDocument = _olderDocuments.isEmpty
                ? firstPage.isEmpty
                      ? null
                      : firstPage.last
                : _olderDocuments.last;
            if (_olderDocuments.isEmpty) {
              _hasMoreDocuments = firstPage.length == _pageSize;
            }
          }
          final allById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
            for (final doc in firstPage) doc.id: doc,
            for (final doc in _olderDocuments) doc.id: doc,
          };
          final all = allById.values.toList();
          final filtered = all.where((d) {
            if (_query.isEmpty) return true;
            final data = d.data();
            final invNo = ((data['invoice'] as Map?)?['number'] ?? '')
                .toString();
            final client = ((data['client'] as Map?)?['name'] ?? '').toString();
            return invNo.toLowerCase().contains(_query) ||
                client.toLowerCase().contains(_query);
          }).toList();

          final invoiceTotalSum = filtered.fold<num>(
            0,
            (sum, d) => (d.data()['kind'] == 'invoice')
                ? sum + ((d.data()['total'] as num?) ?? 0)
                : sum,
          );

          return RefreshIndicator(
            color: primary,
            onRefresh: _refreshDocuments,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverAppBar(
                      toolbarHeight: screenWidth < 600 ? 54 : 58,
                      floating: false,
                      pinned: true,
                      elevation: 0,
                      backgroundColor: surfaceColor,
                      foregroundColor: textMain,
                      title: const Text(
                        'Documents',
                        style: TextStyle(
                          color: MjasiColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                        ),
                      ),
                      actions: [
                        PopupMenuButton<String>(
                          tooltip: 'Invoice options',
                          icon: const Icon(Icons.more_vert),
                          onSelected: (action) {
                            switch (action) {
                              case 'terms':
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const DocumentTermsPage(),
                                  ),
                                );
                                break;
                              case 'design':
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const DocumentDesignPage(),
                                  ),
                                );
                                break;
                              case 'quotation':
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const QuotationPage(),
                                  ),
                                );
                                break;
                              case 'advance':
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const AdvanceInvoicePage(),
                                  ),
                                );
                                break;
                            }
                          },
                          itemBuilder: (_) => [
                            if (BusinessAccessService.can('profile', 'edit'))
                              const PopupMenuItem(
                                value: 'terms',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.description_outlined),
                                  title: Text('Document terms and versions'),
                                ),
                              ),
                            if (BusinessAccessService.can('profile', 'edit'))
                              const PopupMenuItem(
                                value: 'design',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.palette_outlined),
                                  title: Text('Document design and colors'),
                                ),
                              ),
                            if (BusinessAccessService.can(
                              'quotations',
                              'create',
                            ))
                              const PopupMenuItem(
                                value: 'quotation',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.request_quote_outlined),
                                  title: Text('New quotation'),
                                ),
                              ),
                            if (BusinessAccessService.can('invoices', 'create'))
                              const PopupMenuItem(
                                value: 'advance',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.payments_outlined),
                                  title: Text('New advance invoice'),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          screenWidth < 600 ? 14 : 24,
                          12,
                          screenWidth < 600 ? 14 : 24,
                          4,
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Invoices & documents',
                                    style: TextStyle(
                                      color: MjasiColors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Create and manage customer documents',
                                    style: TextStyle(
                                      color: MjasiColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (screenWidth >= 700 &&
                                BusinessAccessService.can(
                                  'invoices',
                                  'create',
                                )) ...[
                              const SizedBox(width: 12),
                              FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const invoice_page.InvoicePage(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('New invoice'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          screenWidth < 600 ? 14 : 24,
                          6,
                          screenWidth < 600 ? 14 : 24,
                          8,
                        ),
                        child: Column(
                          children: [
                            _buildSearchBar(),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _StatCard(
                                  label: 'Loaded documents',
                                  value: '${filtered.length}',
                                  icon: Icons.description_outlined,
                                  color: MjasiColors.primaryBlue,
                                  bgColor: MjasiColors.lightBlue,
                                ),
                                const SizedBox(width: 10),
                                _StatCard(
                                  label: 'Invoice value',
                                  value: 'TSH ${_money(invoiceTotalSum)}',
                                  icon: Icons.account_balance_wallet_outlined,
                                  color: MjasiColors.success,
                                  bgColor: MjasiColors.successBackground,
                                ),
                              ],
                            ),
                            if (BusinessAccessService.can('invoices', 'view') ||
                                BusinessAccessService.can(
                                  'quotations',
                                  'view',
                                )) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => Get.to(
                                    () => DocumentSharesPage(
                                      businessUid:
                                          BusinessAccessService.businessId,
                                    ),
                                  ),
                                  icon: const Icon(Icons.send_outlined),
                                  label: const Text('Sent documents'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primary,
                                    minimumSize: const Size.fromHeight(42),
                                    side: BorderSide(
                                      color: primary.withOpacity(0.25),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyState(
                          onCreate: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const invoice_page.InvoicePage(),
                              ),
                            );
                          },
                          onCreateAdvance: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AdvanceInvoicePage(),
                              ),
                            );
                          },
                          canCreate: BusinessAccessService.can(
                            'invoices',
                            'create',
                          ),
                          primary: primary,
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          screenWidth < 600 ? 14 : 24,
                          8,
                          screenWidth < 600 ? 14 : 24,
                          100,
                        ),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.crossAxisExtent >= 900
                                ? 2
                                : 1;
                            if (columns == 2) {
                              return SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 560,
                                      mainAxisExtent: 202,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 10,
                                    ),
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  return _buildDocumentCard(filtered[index]);
                                }, childCount: filtered.length),
                              );
                            }
                            return SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                i,
                              ) {
                                return _buildDocumentCard(filtered[i]);
                              }, childCount: filtered.length),
                            );
                          },
                        ),
                      ),
                    if (_hasMoreDocuments)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            screenWidth < 600 ? 14 : 24,
                            0,
                            screenWidth < 600 ? 14 : 24,
                            100,
                          ),
                          child: Center(
                            child: OutlinedButton.icon(
                              onPressed: _loadingMoreDocuments
                                  ? null
                                  : _loadMoreDocuments,
                              icon: _loadingMoreDocuments
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.expand_more_rounded),
                              label: Text(
                                _loadingMoreDocuments
                                    ? 'Loading...'
                                    : 'Load more documents',
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(MjasiRadius.sm),
        boxShadow: [
          BoxShadow(
            color: MjasiColors.primaryNavy.withOpacity(0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchC,
        onChanged: (q) => setState(() => _query = q.toLowerCase()),
        style: TextStyle(color: textMain, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search by client or invoice no...',
          hintStyle: TextStyle(color: textMuted, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: primary, size: 20),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 42,
            minHeight: 42,
          ),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.clear, color: textMuted),
                  onPressed: () {
                    _searchC.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MjasiRadius.sm),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: surfaceColor,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final invoice = (data['invoice'] as Map?) ?? {};
    final kind = (data['kind']?.toString() ?? 'invoice');
    final module = kind == 'quotation' ? 'quotations' : 'invoices';
    final canDelete = BusinessAccessService.can(module, 'delete');
    final client = (data['client'] as Map?) ?? {};
    final created = _asDate(data['createdAt']);
    final total = (data['total'] as num?) ?? 0;

    final kindColor = _getColorForKind(kind);
    final kindBg = kindColor.withOpacity(0.09);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(doc.id),
        direction: canDelete
            ? DismissDirection.endToStart
            : DismissDirection.none,
        background: _swipeBg(),
        confirmDismiss: (dir) async {
          if (await _confirmDismiss(context) != true) return false;
          return _restoreStockFor(doc);
        },
        onDismissed: (_) async {
          final deletedInfo = _deletedSummary(doc);
          await doc.reference.delete();
          await NotificationService.notifyOwner(
            action: 'invoice',
            summary: deletedInfo,
          );
          Get.snackbar(
            'Deleted',
            'Document moved to trash',
            snackPosition: SnackPosition.BOTTOM,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(MjasiRadius.sm),
            border: Border.all(color: MjasiColors.border),
            boxShadow: [
              BoxShadow(
                color: MjasiColors.primaryNavy.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(MjasiRadius.sm),
              onTap: () => _previewPdf(data, kind),
              onLongPress: () => _showActions(context, doc),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 36,
                          width: 36,
                          decoration: BoxDecoration(
                            color: kindBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: kindColor.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            _getIconForKind(kind),
                            color: kindColor,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      (client['name'] ?? 'Unknown client')
                                          .toString(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: textMain,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    padding: EdgeInsets.zero,
                                    tooltip: 'Document actions',
                                    icon: Icon(
                                      Icons.more_horiz_rounded,
                                      color: textMuted,
                                      size: 20,
                                    ),
                                    onPressed: () => _showActions(context, doc),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '#${invoice['number'] ?? doc.id.substring(0, 6)}',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kindBg,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _getTitleForKind(kind),
                                      style: TextStyle(
                                        color: kindColor,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Divider(color: MjasiColors.border, height: 1),
                    const SizedBox(height: 7),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final amount = Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Total amount',
                              style: TextStyle(
                                fontSize: 10,
                                color: textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'TSH ${_money(total)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: textMain,
                              ),
                            ),
                          ],
                        );
                        final metadata = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 13,
                                  color: textMuted,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _fmt(created),
                                  style: TextStyle(
                                    color: textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            if ((invoice['paymentMethod'] ?? '')
                                .toString()
                                .isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.payment_outlined,
                                    size: 13,
                                    color: textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      (invoice['paymentMethod'] ?? '')
                                          .toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        );

                        if (constraints.maxWidth < 360) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              metadata,
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: amount,
                              ),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(child: metadata),
                            const SizedBox(width: 12),
                            Flexible(child: amount),
                          ],
                        );
                      },
                    ),
                    if (BusinessAccessService.can(module, 'create') ||
                        BusinessAccessService.can(module, 'edit')) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => showDocumentShareSheet(
                            context: context,
                            businessUid: BusinessAccessService.businessId,
                            documentId: doc.id,
                            document: data,
                          ),
                          icon: const Icon(Icons.chat_outlined, size: 16),
                          label: const Text('Share with customer'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MjasiColors.success,
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            side: const BorderSide(
                              color: MjasiColors.successBackground,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showActions(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final kind = data['kind']?.toString() ?? 'invoice';
    final module = kind == 'quotation' ? 'quotations' : 'invoices';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Document Options',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textMain,
                ),
              ),
              const SizedBox(height: 16),
              if (BusinessAccessService.can(module, 'edit'))
                _ActionTile(
                  icon: Icons.edit_outlined,
                  title: 'Edit Document',
                  color: textMain,
                  onTap: () {
                    Navigator.pop(context);
                    _editInvoice(doc);
                  },
                ),
              _ActionTile(
                icon: Icons.visibility_outlined,
                title: 'Preview PDF',
                color: textMain,
                onTap: () {
                  Navigator.pop(context);
                  _previewPdf(data, kind);
                },
              ),
              _ActionTile(
                icon: Icons.download_outlined,
                title: 'Download Original PDF',
                color: textMain,
                onTap: () {
                  Navigator.pop(context);
                  _savePdf(data, kind);
                },
              ),
              if (BusinessAccessService.can(module, 'create') ||
                  BusinessAccessService.can(module, 'edit'))
                _ActionTile(
                  icon: Icons.chat_outlined,
                  title: 'Share customer link on WhatsApp',
                  color: const Color(0xFF168A62),
                  onTap: () {
                    Navigator.pop(context);
                    Future<void>.delayed(Duration.zero, () {
                      if (!mounted) return;
                      showDocumentShareSheet(
                        context: context,
                        businessUid: BusinessAccessService.businessId,
                        documentId: doc.id,
                        document: data,
                      );
                    });
                  },
                ),
              Divider(color: Colors.grey.shade100, height: 24),
              ExpansionTile(
                leading: Icon(Icons.file_copy_outlined, color: textMain),
                title: Text(
                  'Generate As...',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: textMain,
                  ),
                ),
                childrenPadding: const EdgeInsets.only(left: 16),
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  _ActionTile(
                    icon: Icons.arrow_right,
                    title: 'Invoice',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _savePdf(data, 'invoice');
                    },
                  ),
                  _ActionTile(
                    icon: Icons.arrow_right,
                    title: 'Quotation',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _savePdf(data, 'quotation');
                    },
                  ),
                  _ActionTile(
                    icon: Icons.arrow_right,
                    title: 'Proforma',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _savePdf(data, 'proforma');
                    },
                  ),
                  _ActionTile(
                    icon: Icons.arrow_right,
                    title: 'Delivery Note',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _savePdf(data, 'delivery');
                    },
                  ),
                  _ActionTile(
                    icon: Icons.arrow_right,
                    title: 'Payment Reminder',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _savePdf(data, 'reminder');
                    },
                  ),
                  _ActionTile(
                    icon: Icons.arrow_right,
                    title: 'Advance Payment',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _savePdf(data, 'advance');
                    },
                  ),
                  _ActionTile(
                    icon: Icons.table_chart_outlined,
                    title: 'Export as Excel',
                    color: textMuted,
                    onTap: () {
                      Navigator.pop(context);
                      _saveAsExcel(data);
                    },
                  ),
                ],
              ),
              Divider(color: Colors.grey.shade100, height: 24),
              if (BusinessAccessService.can(module, 'delete'))
                _ActionTile(
                  icon: Icons.delete_outline,
                  title: 'Delete Document',
                  color: Colors.red,
                  onTap: () async {
                    Navigator.pop(context);
                    final ok = await _confirmDismiss(context);
                    if (ok == true && await _restoreStockFor(doc)) {
                      final deletedInfo = _deletedSummary(doc);
                      await doc.reference.delete();
                      await NotificationService.notifyOwner(
                        action: 'invoice',
                        summary: deletedInfo,
                      );
                      Get.snackbar(
                        'Deleted',
                        'Document removed',
                        snackPosition: SnackPosition.BOTTOM,
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  static DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static String _fmt(DateTime? d) {
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year}';
  }

  Widget _swipeBg() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade400,
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Icon(Icons.delete_outline, color: Colors.white, size: 32),
    );
  }

  /// Returns stock sold by this document before it is deleted (idempotent).
  Future<bool> _restoreStockFor(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    try {
      await StockService.reverseSaleForDocument(doc);
      return true;
    } catch (e) {
      Get.snackbar(
        'error'.tr,
        stockErrorText(e),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return false;
    }
  }

  Future<bool?> _confirmDismiss(BuildContext context) async {
    return await Get.dialog<bool>(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade400),
            const SizedBox(width: 8),
            const Text('Delete Document?'),
          ],
        ),
        content: const Text(
          'This action cannot be undone. Are you sure you want to proceed?',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Get.back(result: true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  static String _money(num v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  Color _getColorForKind(String kind) {
    return switch (kind) {
      'proforma' => MjasiColors.warning,
      'quotation' => MjasiColors.secondaryBlue,
      'delivery' => MjasiColors.success,
      'reminder' => MjasiColors.error,
      'advance' => MjasiColors.primaryNavy,
      _ => primary,
    };
  }

  IconData _getIconForKind(String kind) {
    return switch (kind) {
      'proforma' => Icons.request_quote_outlined,
      'quotation' => Icons.request_quote,
      'delivery' => Icons.local_shipping_outlined,
      'reminder' => Icons.alarm_on_outlined,
      'advance' => Icons.payments_outlined,
      _ => Icons.receipt_long, // invoice
    };
  }

  String _getTitleForKind(String kind) {
    return switch (kind) {
      'proforma' => 'Proforma',
      'quotation' => 'Quotation',
      'delivery' => 'Delivery Note',
      'reminder' => 'Reminder',
      'advance' => 'Advance Payment Invoice',
      _ => 'Invoice',
    };
  }

  void _savePdf(Map<String, dynamic> data, String kind) async {
    try {
      final clean = Map<String, dynamic>.from(data);
      final ts = clean['createdAt'];
      if (ts is Timestamp) clean['createdAt'] = ts.toDate().toIso8601String();

      final no = (clean['invoice'] as Map?)?['number']?.toString();
      final fileNameBase = (no == null || no.isEmpty)
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : no;
      final fileName = '${kind}_$fileNameBase.pdf';

      final pathOrName = await ({
        'invoice': () => InvoicePdf.generateAndSave(clean, fileName: fileName),
        'proforma': () =>
            ProformaPdf.generateAndSave(clean, fileName: fileName),
        'delivery': () =>
            DeliveryNotePdf.generateAndSave(clean, fileName: fileName),
        'reminder': () =>
            PaymentReminderPdf.generateAndSave(clean, fileName: fileName),
        'advance': () =>
            AdvancePaymentPdf.generateAndSave(clean, fileName: fileName),
        'quotation': () =>
            QuotationPdf.generateAndSave(clean, fileName: fileName),
      }[kind]!).call();

      Get.snackbar(
        kIsWeb ? 'PDF downloaded' : 'PDF saved',
        pathOrName,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to save PDF: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _previewPdf(Map<String, dynamic> data, String kind) async {
    try {
      await ({
        'invoice': () => InvoicePdf.generate(data),
        'proforma': () => ProformaPdf.generate(data),
        'delivery': () => DeliveryNotePdf.generate(data),
        'reminder': () => PaymentReminderPdf.generate(data),
        'advance': () => AdvancePaymentPdf.generate(data),
        'quotation': () => QuotationPdf.generate(data),
      }[kind]!).call();
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to generate preview: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _saveAsExcel(Map<String, dynamic> data) async {
    try {
      Get.snackbar(
        'Excel export',
        'Excel export is not available in this build.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to save Excel file: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _editInvoice(DocumentSnapshot<Map<String, dynamic>> doc) {
    final module = doc.data()?['kind']?.toString() == 'quotation'
        ? 'quotations'
        : 'invoices';
    if (!BusinessAccessService.can(module, 'edit')) {
      Get.snackbar('Error', 'staff_no_permission'.tr);
      return;
    }
    if (module == 'quotations') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => QuotationPage(quotation: doc)));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => invoice_page.InvoicePage(invoice: doc)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onCreate,
    required this.onCreateAdvance,
    required this.canCreate,
    required this.primary,
  });

  final VoidCallback onCreate;
  final VoidCallback onCreateAdvance;
  final bool canCreate;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.09),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.description_outlined,
                  size: 52,
                  color: primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No documents yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: MjasiColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Create your first invoice or quotation to keep track of your business.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: MjasiColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              if (canCreate)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(MjasiRadius.sm),
                    ),
                    elevation: 0,
                  ),
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    'Create New Document',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              if (canCreate) const SizedBox(height: 6),
              if (canCreate)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(MjasiRadius.sm),
                    ),
                  ),
                  onPressed: onCreateAdvance,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text(
                    'Create Advance Invoice',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: MjasiColors.surface,
          borderRadius: BorderRadius.circular(MjasiRadius.sm),
          border: Border.all(color: MjasiColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: MjasiColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color color;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}
