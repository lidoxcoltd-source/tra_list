import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// Relative time for recent posts, absolute date and time for older ones.
String marketPostedAgo(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'market_just_now'.tr;
  if (diff.inMinutes < 60) return '${diff.inMinutes} min';
  if (diff.inHours < 24) return '${diff.inHours} h';
  return DateFormat('dd MMM yyyy, HH:mm').format(time);
}

const marketCategories = <String>[
  'food',
  'fashion',
  'electronics',
  'home',
  'beauty',
  'services',
  'other',
];

final _hashtagPattern = RegExp(r'#([\p{L}\p{N}_]{2,40})', unicode: true);

const marketSuggestedHashtags = <String>[
  'chakula',
  'mavazi',
  'electronics',
  'nyumbani',
  'urembo',
  'huduma',
  'punguzo',
];

/// Lower-cased unique hashtags (without '#') found in [text], in order.
List<String> extractHashtags(String text) {
  final seen = <String>{};
  for (final match in _hashtagPattern.allMatches(text)) {
    seen.add(match.group(1)!.toLowerCase());
  }
  return seen.toList();
}

String normalizeHashtag(String tag) =>
    tag.trim().replaceFirst(RegExp(r'^#+'), '').toLowerCase();

class MarketStatusGroup {
  const MarketStatusGroup({
    required this.authorUid,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.statuses,
  });

  final String authorUid;
  final String authorName;
  final String authorPhotoUrl;
  final List<MarketPost> statuses;
}

class MarketProfile {
  const MarketProfile({
    required this.uid,
    required this.name,
    this.category = '',
    this.bio = '',
    this.city = '',
    this.photoUrl = '',
    this.whatsapp = '',
    this.followersCount = 0,
    this.followingCount = 0,
    this.postsCount = 0,
  });

  final String uid;
  final String name;
  final String category;
  final String bio;
  final String city;
  final String photoUrl;
  final String whatsapp;
  final int followersCount;
  final int followingCount;
  final int postsCount;

  factory MarketProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return MarketProfile(
      uid: doc.id,
      name: (data['name'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      bio: (data['bio'] ?? '').toString(),
      city: (data['city'] ?? '').toString(),
      photoUrl: (data['photoUrl'] ?? '').toString(),
      whatsapp: (data['whatsapp'] ?? '').toString(),
      followersCount: (data['followersCount'] as num?)?.toInt() ?? 0,
      followingCount: (data['followingCount'] as num?)?.toInt() ?? 0,
      postsCount: (data['postsCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class MarketBusinessDocument {
  const MarketBusinessDocument({
    required this.type,
    required this.fileName,
    required this.url,
    required this.storagePath,
    required this.contentType,
    this.uploadedAt,
  });

  final String type;
  final String fileName;
  final String url;
  final String storagePath;
  final String contentType;
  final DateTime? uploadedAt;

  factory MarketBusinessDocument.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return MarketBusinessDocument(
      type: (data['type'] ?? doc.id).toString(),
      fileName: (data['fileName'] ?? '').toString(),
      url: (data['url'] ?? '').toString(),
      storagePath: (data['storagePath'] ?? '').toString(),
      contentType: (data['contentType'] ?? '').toString(),
      uploadedAt: (data['uploadedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class MarketBusinessReview {
  const MarketBusinessReview({
    required this.profile,
    required this.documents,
    required this.verified,
  });

  final MarketProfile profile;
  final List<MarketBusinessDocument> documents;
  final bool verified;

  DateTime? get submittedAt {
    DateTime? latest;
    for (final document in documents) {
      final at = document.uploadedAt;
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    return latest;
  }
}

class MarketPost {
  const MarketPost({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.type,
    required this.images,
    this.authorPhotoUrl = '',
    this.caption = '',
    this.category = '',
    this.productName = '',
    this.productId = '',
    this.productOwnerUid = '',
    this.price,
    this.currency = 'TZS',
    this.purchaseMethod = '',
    this.inStock = true,
    this.whatsapp = '',
    this.likesCount = 0,
    this.commentsCount = 0,
    this.viewsCount = 0,
    this.createdAt,
    this.expiresAt,
    this.audioUrl = '',
    this.audioTitle = '',
    this.publishAt,
    this.videoUrl = '',
    this.videoThumb = '',
    this.textBg = -1,
    this.textFont = 0,
  });

  final String videoUrl;
  final String videoThumb;
  final int textBg;
  final int textFont;
  bool get hasVideo => videoUrl.isNotEmpty;
  bool get isTextOnly => images.isEmpty && videoUrl.isEmpty;
  final DateTime? publishAt;
  bool get isScheduled =>
      publishAt != null && publishAt!.isAfter(DateTime.now());
  final String audioUrl;
  final String audioTitle;
  final String id;
  final String authorUid;
  final String authorName;
  final String authorPhotoUrl;
  final String type;
  final String caption;
  final String category;
  final List<String> images;
  final String productName;
  final String productId;
  final String productOwnerUid;
  final num? price;
  final String currency;
  final String purchaseMethod;
  final bool inStock;
  final String whatsapp;
  final int likesCount;
  final int commentsCount;
  final int viewsCount;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool get isProduct => type == 'product';
  List<String> get hashtags => extractHashtags(caption);
  bool get isStatus => type == 'status';
  bool isActiveStatusAt(DateTime now) =>
      isStatus && expiresAt != null && expiresAt!.isAfter(now);

  Map<String, dynamic> toMap() => {
    'authorUid': authorUid,
    'authorName': authorName,
    'authorPhotoUrl': authorPhotoUrl,
    'type': type,
    'caption': caption,
    'category': category,
    'images': images,
    'productName': productName,
    'productId': productId,
    'productOwnerUid': productOwnerUid,
    'price': price,
    'currency': currency,
    'purchaseMethod': purchaseMethod,
    'inStock': inStock,
    'whatsapp': whatsapp,
    'likesCount': likesCount,
    'commentsCount': commentsCount,
    'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
    'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
    if (audioUrl.isNotEmpty) 'audioUrl': audioUrl,
    if (audioUrl.isNotEmpty) 'audioTitle': audioTitle,
    if (publishAt != null) 'publishAt': Timestamp.fromDate(publishAt!),
    if (videoUrl.isNotEmpty) 'videoUrl': videoUrl,
    if (textBg >= 0) 'textBg': textBg,
    if (textFont > 0) 'textFont': textFont,
  };

  factory MarketPost.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return MarketPost.fromData(doc.id, doc.data() ?? const {});
  }

  factory MarketPost.fromData(String id, Map<String, dynamic> data) {
    return MarketPost(
      id: id,
      authorUid: (data['authorUid'] ?? '').toString(),
      authorName: (data['authorName'] ?? '').toString(),
      authorPhotoUrl: (data['authorPhotoUrl'] ?? '').toString(),
      type: (data['type'] ?? 'post').toString(),
      caption: (data['caption'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      images: [
        for (final image in (data['images'] as List? ?? const []))
          image.toString(),
      ],
      productName: (data['productName'] ?? '').toString(),
      productId: (data['productId'] ?? '').toString(),
      productOwnerUid: (data['productOwnerUid'] ?? '').toString(),
      price: (data['price'] as num?) != null && (data['price'] as num) > 0
          ? data['price'] as num
          : null,
      currency: (data['currency'] ?? 'TZS').toString(),
      purchaseMethod: (data['purchaseMethod'] ?? '').toString(),
      inStock: data['inStock'] != false,
      whatsapp: (data['whatsapp'] ?? '').toString(),
      likesCount: (data['likesCount'] as num?)?.toInt() ?? 0,
      commentsCount: (data['commentsCount'] as num?)?.toInt() ?? 0,
      viewsCount: (data['viewsCount'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
      audioUrl: (data['audioUrl'] ?? '').toString(),
      audioTitle: (data['audioTitle'] ?? '').toString(),
      publishAt: (data['publishAt'] as Timestamp?)?.toDate(),
      videoUrl: (data['videoUrl'] ?? '').toString(),
      videoThumb: (data['videoThumb'] ?? '').toString(),
      textBg: (data['textBg'] as num?)?.toInt() ?? -1,
      textFont: (data['textFont'] as num?)?.toInt() ?? 0,
    );
  }
}

String marketPostUrl(MarketPost post) =>
    'https://mjasipos.web.app/#/market/post/${post.id}';

String buildMarketWhatsAppMessage(MarketPost post, {int? quantity}) {
  final isSwahili = Get.locale?.languageCode == 'sw';
  final message = <String>[
    isSwahili
        ? 'Habari, naulizia ${post.productName} hapo.'
        : 'Hello, I am asking about ${post.productName}.',
    if (post.authorName.isNotEmpty)
      '${isSwahili ? 'Duka' : 'Shop'}: ${post.authorName}',
    if (post.price != null)
      '${isSwahili ? 'Bei' : 'Price'}: ${post.currency} ${post.price}',
    if (post.category.isNotEmpty)
      '${isSwahili ? 'Aina' : 'Category'}: ${post.category}',
    if (post.caption.trim().isNotEmpty)
      '${isSwahili ? 'Maelezo' : 'Details'}: ${post.caption.trim()}',
    if (post.isProduct)
      '${isSwahili ? 'Upatikanaji' : 'Availability'}: '
          '${post.inStock ? (isSwahili ? 'Inapatikana' : 'In stock') : (isSwahili ? 'Haipatikani' : 'Out of stock')}',
    if (quantity != null && quantity > 0)
      '${isSwahili ? 'Idadi' : 'Quantity'}: $quantity',
    '${isSwahili ? 'Kiungo cha post' : 'Post link'}: ${marketPostUrl(post)}',
  ];
  return message.join('\n');
}
