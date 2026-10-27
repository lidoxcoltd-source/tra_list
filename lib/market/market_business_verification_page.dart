import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import 'market_models.dart';
import 'market_service.dart';

enum _ReviewFilter { pending, verified, all }

class MarketBusinessVerificationPage extends StatefulWidget {
  const MarketBusinessVerificationPage({super.key});

  @override
  State<MarketBusinessVerificationPage> createState() =>
      _MarketBusinessVerificationPageState();
}

class _MarketBusinessVerificationPageState
    extends State<MarketBusinessVerificationPage> {
  bool _loading = true;
  bool _authorized = false;
  String? _error;
  List<MarketBusinessReview> _reviews = [];
  final Set<String> _updating = {};
  final _searchController = TextEditingController();
  _ReviewFilter _filter = _ReviewFilter.pending;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MarketBusinessReview> get _visible {
    final term = _searchController.text.trim().toLowerCase();
    return _reviews.where((review) {
      final matchesFilter = switch (_filter) {
        _ReviewFilter.pending => !review.verified,
        _ReviewFilter.verified => review.verified,
        _ReviewFilter.all => true,
      };
      if (!matchesFilter) return false;
      if (term.isEmpty) return true;
      return review.profile.name.toLowerCase().contains(term) ||
          review.profile.city.toLowerCase().contains(term) ||
          review.profile.uid.toLowerCase().contains(term);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('admin_market_verification_denied'.tr);
      final profile = await FirebaseFirestore.instance
          .doc('users/${user.uid}/profile/company')
          .get();
      final role = (profile.data()?['role']?.toString() ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (role != 'superadmin') {
        if (!mounted) return;
        setState(() {
          _authorized = false;
          _loading = false;
        });
        return;
      }
      final reviews = await MarketService.loadBusinessReviews();
      if (!mounted) return;
      setState(() {
        _authorized = true;
        _reviews = reviews;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setVerified(MarketBusinessReview review, bool verified) async {
    final uid = review.profile.uid;
    setState(() => _updating.add(uid));
    try {
      await MarketService.setBusinessVerified(
        businessUid: uid,
        verified: verified,
      );
      if (!mounted) return;
      setState(() {
        _reviews = [
          for (final item in _reviews)
            if (item.profile.uid == uid)
              MarketBusinessReview(
                profile: item.profile,
                documents: item.documents,
                verified: verified,
              )
            else
              item,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('admin_market_verification_saved'.tr)),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'admin_market_verification_error'.trParams({'error': '$error'}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updating.remove(uid));
    }
  }

  Future<void> _openDocument(MarketBusinessDocument document) async {
    final uri = Uri.tryParse(document.url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('market_document_open_error'.tr)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MjasiColors.background,
      appBar: AppBar(
        title: Text('admin_market_verification_title'.tr),
        actions: [
          IconButton(
            tooltip: 'refresh'.tr,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_authorized
          ? _stateMessage(
              Icons.lock_outline_rounded,
              'admin_market_verification_denied'.tr,
            )
          : _error != null
          ? _stateMessage(
              Icons.cloud_off_rounded,
              _error!,
              action: FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('market_retry'.tr),
              ),
            )
          : _buildContent(),
    );
  }

  Widget _stateMessage(IconData icon, String text, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: MjasiColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MjasiColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final pending = _reviews.where((r) => !r.verified).length;
    final verified = _reviews.length - pending;
    final visible = _visible;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _statTile(
                      'admin_market_verification_pending'.tr,
                      pending,
                      MjasiColors.warning,
                      MjasiColors.warningBackground,
                      Icons.hourglass_top_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _statTile(
                      'admin_market_verification_approved'.tr,
                      verified,
                      MjasiColors.success,
                      MjasiColors.successBackground,
                      Icons.verified_rounded,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'admin_market_verification_search'.tr,
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: MjasiColors.surface,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MjasiRadius.pill),
                    borderSide: const BorderSide(color: MjasiColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MjasiRadius.pill),
                    borderSide: const BorderSide(color: MjasiColors.border),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final filter in _ReviewFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(switch (filter) {
                          _ReviewFilter.pending =>
                            'admin_market_verification_pending'.tr,
                          _ReviewFilter.verified =>
                            'admin_market_verification_approved'.tr,
                          _ReviewFilter.all => 'admin_market_filter_all'.tr,
                        }),
                        selected: _filter == filter,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _filter = filter),
                        selectedColor: MjasiColors.primaryNavy,
                        backgroundColor: MjasiColors.surface,
                        side: const BorderSide(color: MjasiColors.border),
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _filter == filter
                              ? Colors.white
                              : MjasiColors.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: visible.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 80),
                          _stateMessage(
                            Icons.inbox_outlined,
                            'admin_market_verification_empty'.tr,
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) =>
                            _reviewCard(visible[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(
    String label,
    int value,
    Color color,
    Color background,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(MjasiRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(bool verified) {
    final color = verified ? MjasiColors.success : MjasiColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: verified
            ? MjasiColors.successBackground
            : MjasiColors.warningBackground,
        borderRadius: BorderRadius.circular(MjasiRadius.pill),
      ),
      child: Text(
        verified
            ? 'admin_market_verification_approved'.tr
            : 'admin_market_verification_pending'.tr,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _reviewCard(MarketBusinessReview review) {
    final profile = review.profile;
    final busy = _updating.contains(profile.uid);
    final name = profile.name.isEmpty
        ? 'admin_market_verification_unnamed'.tr
        : profile.name;
    final submitted = review.submittedAt;
    final meta = [
      if (profile.city.isNotEmpty) profile.city,
      if (submitted != null)
        '${'admin_market_verification_submitted'.tr} '
            '${DateFormat('dd MMM yyyy').format(submitted)}',
    ].join(' · ');
    return Container(
      decoration: BoxDecoration(
        color: MjasiColors.surface,
        borderRadius: BorderRadius.circular(MjasiRadius.md),
        border: Border.all(color: MjasiColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: MjasiColors.lightBlue,
                foregroundImage: profile.photoUrl.isEmpty
                    ? null
                    : NetworkImage(profile.photoUrl),
                child: profile.photoUrl.isEmpty
                    ? const Icon(
                        Icons.storefront_rounded,
                        color: MjasiColors.primaryBlue,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: MjasiColors.textPrimary,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: MjasiColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              _statusBadge(review.verified),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'admin_market_verification_documents'.tr,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: MjasiColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          for (final document in review.documents)
            InkWell(
              borderRadius: BorderRadius.circular(MjasiRadius.sm),
              onTap: () => _openDocument(document),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: MjasiColors.background,
                  borderRadius: BorderRadius.circular(MjasiRadius.sm),
                ),
                child: Row(
                  children: [
                    Icon(
                      document.contentType == 'application/pdf'
                          ? Icons.picture_as_pdf_outlined
                          : Icons.image_outlined,
                      size: 20,
                      color: MjasiColors.primaryBlue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'market_document_${document.type}'.tr,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            document.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: MjasiColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: MjasiColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: review.verified
                ? OutlinedButton.icon(
                    onPressed: busy ? null : () => _setVerified(review, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MjasiColors.error,
                    ),
                    icon: busy ? _spinner() : const Icon(Icons.block_rounded),
                    label: Text('admin_market_verification_revoke'.tr),
                  )
                : FilledButton.icon(
                    onPressed: busy ? null : () => _setVerified(review, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: MjasiColors.success,
                    ),
                    icon: busy
                        ? _spinner()
                        : const Icon(Icons.verified_rounded),
                    label: Text('admin_market_verification_approve'.tr),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _spinner() => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
