import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/routes.dart';
import 'package:tra_list/theme/app_theme.dart';
import 'stock_media.dart';
import 'stock_models.dart';

const kStockNavy = MjasiColors.primaryNavy;
const kStockBlue = MjasiColors.primaryBlue;
const kStockLight = MjasiColors.lightBlue;
const kStockBg = MjasiColors.background;
const kStockOk = MjasiColors.success;
const kStockWarn = MjasiColors.warning;
const kStockBad = MjasiColors.error;

String fmtText(String key, Map<String, String> values) {
  var text = key.tr;
  values.forEach((k, v) => text = text.replaceAll('@$k', v));
  return text;
}

String unitLabel(String unit) {
  final key = 'stk_unit_$unit';
  final t = key.tr;
  return t == key ? unit : t;
}

/// Translates StockException keys (and shows other errors verbatim).
String stockErrorText(Object error) {
  if (error is StockException) return fmtText(error.messageKey, error.args);
  return '$error';
}

void stockToast(String title, String message, {bool error = false}) {
  Get.snackbar(
    title,
    message,
    snackPosition: SnackPosition.BOTTOM,
    backgroundColor: error ? kStockBad : kStockOk,
    colorText: Colors.white,
    margin: const EdgeInsets.all(12),
    maxWidth: 520,
  );
}

void stockGoBack(BuildContext context) {
  if (Navigator.of(context).canPop()) {
    Get.back();
  } else {
    Get.offAllNamed(AppRoutes.home);
  }
}

class StockScaffold extends StatelessWidget {
  const StockScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.fab,
    this.bottom,
    this.maxWidth = 1100,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;
  final PreferredSizeWidget? bottom;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kStockBg,
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 8,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 17,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: kStockNavy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
        ),
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: .12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            onPressed: () => stockGoBack(context),
          ),
        ),
        actions: actions
            ?.map(
              (action) => IconTheme(
                data: const IconThemeData(color: Colors.white),
                child: action,
              ),
            )
            .toList(),
        bottom: bottom,
      ),
      floatingActionButton: fab,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox(width: double.infinity, child: body),
        ),
      ),
    );
  }
}

class StockSectionHeading extends StatelessWidget {
  const StockSectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MjasiColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.15,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class StockCard extends StatelessWidget {
  const StockCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor,
    this.height,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 1,
      shadowColor: const Color(0x12071B3A),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor ?? MjasiColors.border),
          ),
          child: height == null
              ? child
              : SizedBox(height: height, child: child),
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = kStockBlue,
    this.caption,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return StockCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      height: 124,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              if (onTap != null)
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: MjasiColors.textSecondary.withValues(alpha: .75),
                ),
            ],
          ),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MjasiColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                letterSpacing: -0.5,
                fontWeight: FontWeight.w800,
                color: MjasiColors.textPrimary,
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MjasiColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class StockStateChip extends StatelessWidget {
  const StockStateChip({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    if (!product.tracked) {
      return _chip('stk_not_tracked'.tr, Colors.blueGrey);
    }
    return switch (product.stockState) {
      StockState.out => _chip('stk_out_of_stock'.tr, kStockBad),
      StockState.low => _chip('stk_low_stock'.tr, kStockWarn),
      StockState.ok => _chip('stk_in_stock'.tr, kStockOk),
    };
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: color.withValues(alpha: .14)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 11,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class StockMessage extends StatelessWidget {
  const StockMessage({
    super.key,
    required this.icon,
    required this.text,
    this.color = Colors.grey,
    this.action,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 36, color: color.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 18),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MjasiColors.textSecondary,
                height: 1.45,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

InputDecoration stockInput(String label, {IconData? icon, String? suffix}) =>
    InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      suffixText: suffix,
      filled: true,
      fillColor: MjasiColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MjasiColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MjasiColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kStockBlue, width: 1.5),
      ),
    );

Color movementColor(MovementType t, double change) =>
    change >= 0 ? kStockOk : kStockBad;

String formatDate(DateTime? d) => d == null
    ? ''
    : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String formatDateTime(DateTime? d) => d == null
    ? ''
    : '${formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Searchable product picker. Returns null when dismissed.
Future<Product?> pickProduct(
  BuildContext context,
  List<Product> products, {
  bool trackedOnly = false,
}) {
  final list = products
      .where((p) => p.active && (!trackedOnly || p.tracked))
      .toList();
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(
        builder: (ctx, setState) {
          final q = query.trim().toLowerCase();
          final shown = list
              .where(
                (p) =>
                    q.isEmpty ||
                    p.name.toLowerCase().contains(q) ||
                    p.sku.toLowerCase().contains(q) ||
                    p.barcode.toLowerCase().contains(q),
              )
              .toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.78,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 14),
                      child: TextField(
                        autofocus: true,
                        decoration:
                            stockInput(
                              'stk_search'.tr,
                              icon: Icons.search_rounded,
                            ).copyWith(
                              suffixIcon: IconButton(
                                tooltip: 'stk_scan'.tr,
                                icon: const Icon(Icons.qr_code_scanner),
                                onPressed: () async {
                                  final p = await scanForProduct(
                                    ctx,
                                    list,
                                    trackedOnly: trackedOnly,
                                  );
                                  if (p != null && ctx.mounted) {
                                    Navigator.pop(ctx, p);
                                  }
                                },
                              ),
                            ),
                        onChanged: (v) => setState(() => query = v),
                      ),
                    ),
                    Expanded(
                      child: shown.isEmpty
                          ? StockMessage(
                              icon: Icons.inventory_2_outlined,
                              text: 'stk_no_products'.tr,
                            )
                          : ListView.separated(
                              itemCount: shown.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final p = shown[i];
                                return ListTile(
                                  leading: ProductImage(
                                    url: p.imageUrl,
                                    size: 40,
                                    radius: 12,
                                  ),
                                  title: Text(p.name),
                                  subtitle: Text(
                                    '${p.sku} · ${p.tracked ? '${formatQty(p.quantity)} ${unitLabel(p.unit)}' : 'stk_not_tracked'.tr}',
                                  ),
                                  trailing: StockStateChip(product: p),
                                  onTap: () => Navigator.pop(ctx, p),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
