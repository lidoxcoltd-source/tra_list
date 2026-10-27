import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'market_models.dart';
import 'market_profile_page.dart';
import 'market_service.dart';
import 'market_palette.dart';

class MarketFollowListPage extends StatefulWidget {
  const MarketFollowListPage({
    super.key,
    required this.uid,
    required this.followers,
  });

  final String uid;
  final bool followers;

  @override
  State<MarketFollowListPage> createState() => _MarketFollowListPageState();
}

class _MarketFollowListPageState extends State<MarketFollowListPage> {
  final _searchController = TextEditingController();
  late Future<List<MarketProfile>> _profiles;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  void _loadProfiles() {
    _profiles = MarketService.searchFollowProfiles(
      uid: widget.uid,
      followers: widget.followers,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MarketProfile> _filterProfiles(List<MarketProfile> profiles) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return profiles;
    return profiles.where((profile) {
      return profile.name.toLowerCase().contains(query) ||
          profile.bio.toLowerCase().contains(query) ||
          profile.city.toLowerCase().contains(query) ||
          profile.category.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.followers
        ? 'market_followers'.tr
        : 'market_following_count'.tr;
    return Theme(
      data: MarketPalette.darkTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: MarketPalette.canvas,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: MarketPalette.topBar,
          foregroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'market_search_people'.tr,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).deleteButtonTooltip,
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: MarketPalette.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: MarketPalette.border,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: MarketPalette.border,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: MarketPalette.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FutureBuilder<List<MarketProfile>>(
                        future: _profiles,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const SizedBox.shrink();
                          final count = _filterProfiles(snapshot.data!).length;
                          return Text(
                            '$count',
                            style: const TextStyle(
                              color: MarketPalette.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<MarketProfile>>(
                    future: _profiles,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_off_outlined,
                                color: MarketPalette.textMuted,
                                size: 36,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'explore_error'.tr,
                                style: const TextStyle(
                                  color: MarketPalette.textMuted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () => setState(_loadProfiles),
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text('market_retry'.tr),
                              ),
                            ],
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final profiles = _filterProfiles(snapshot.data!);
                      if (profiles.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.people_outline_rounded,
                                  color: MarketPalette.textMuted,
                                  size: 38,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _query.isEmpty
                                      ? 'market_follow_list_empty'.tr
                                      : 'market_no_people_match'.tr,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: MarketPalette.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: profiles.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          indent: 64,
                          color: MarketPalette.border,
                        ),
                        itemBuilder: (context, index) {
                          final profile = profiles[index];
                          final subtitle = profile.city.isNotEmpty
                              ? profile.city
                              : profile.bio;
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => Get.to(
                              () => MarketProfilePage(uid: profile.uid),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 23,
                                    backgroundColor:
                                        MarketPalette.surfaceRaised,
                                    foregroundImage: profile.photoUrl.isEmpty
                                        ? null
                                        : NetworkImage(profile.photoUrl),
                                    child: profile.photoUrl.isEmpty
                                        ? Text(
                                            profile.name.trim().isEmpty
                                                ? '?'
                                                : profile.name
                                                      .trim()[0]
                                                      .toUpperCase(),
                                            style: const TextStyle(
                                              color: MarketPalette.blue,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          profile.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: MarketPalette.text,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (subtitle.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: MarketPalette.textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: MarketPalette.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
