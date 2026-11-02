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

const double _stockRadius = 14;
const double _stockPagePadding = 16;

String fmtText(String key, Map<String, String> values) {
  var text = key.tr;
  values.forEach((key, value) {
    text = text.replaceAll('@$key', value);
  });
  return text;
}

String unitLabel(String unit) {
  final key = 'stk_unit_$unit';
  final translated = key.tr;
  return translated == key ? unit : translated;
}

/// Translates StockException keys and displays other errors verbatim.
String stockErrorText(Object error) {
  if (error is StockException) {
    return fmtText(error.messageKey, error.args);
  }
  return '$error';
}

void stockToast(
  String title,
  String message, {
  bool error = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  Get.snackbar(
    title,
    message,
    snackPosition: SnackPosition.BOTTOM,
    backgroundColor: error ? kStockBad : kStockNavy,
    colorText: Colors.white,
    margin: const EdgeInsets.all(12),
    maxWidth: 520,
    borderRadius: 12,
    duration: Duration(seconds: onAction == null ? 3 : 8),
    mainButton: onAction == null || actionLabel == null
        ? null
        : TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
  );
}

void stockGoBack(BuildContext context) {
  if (Navigator.of(context).canPop()) {
    Get.back();
  } else {
    Get.offAllNamed(AppRoutes.home);
  }
}

/// Shared page scaffold for all stock-management screens.
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
        toolbarHeight: 58,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: kStockNavy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 4,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3,
          ),
        ),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => stockGoBack(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 21),
        ),
        actions: actions,
        bottom: bottom,
      ),
      floatingActionButton: fab,
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SizedBox(width: double.infinity, child: body),
          ),
        ),
      ),
    );
  }
}

/// Consistent section title with optional helper text and trailing action.
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
      padding: const EdgeInsets.only(bottom: 12),
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
                    letterSpacing: -.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: MjasiColors.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

/// Neutral surface card. Keeps the existing StockCard API intact.
class StockCard extends StatelessWidget {
  const StockCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
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
      borderRadius: BorderRadius.circular(_stockRadius),
      elevation: onTap == null ? 0.5 : 1,
      shadowColor: kStockNavy.withValues(alpha: .08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_stockRadius),
        child: Container(
          padding: padding,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_stockRadius),
            border: Border.all(
              color: borderColor ?? MjasiColors.border,
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Compact statistic tile for dashboards and stock summaries.
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MjasiColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MjasiColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.3,
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
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: MjasiColors.textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// Small, low-contrast status label for product stock state.
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

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Reusable empty/error/info state.
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 28, color: color.withValues(alpha: .85)),
            ),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MjasiColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

/// Shared input style used throughout stock forms.
InputDecoration stockInput(String label, {IconData? icon, String? suffix}) {
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: MjasiColors.border),
  );

  return InputDecoration(
    labelText: label,
    prefixIcon: icon == null ? null : Icon(icon, size: 19),
    suffixText: suffix,
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
    border: outline,
    enabledBorder: outline,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kStockBlue, width: 1.4),
    ),
  );
}

Color movementColor(MovementType type, double change) {
  return change >= 0 ? kStockOk : kStockBad;
}

String formatDate(DateTime? date) {
  if (date == null) return '';
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
}

String formatDateTime(DateTime? date) {
  if (date == null) return '';
  return '${formatDate(date)} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

/// Searchable product picker. Returns null when dismissed.
Future<Product?> pickProduct(
  BuildContext context,
  List<Product> products, {
  bool trackedOnly = false,
}) {
  final availableProducts = products
      .where((product) => product.active && (!trackedOnly || product.tracked))
      .toList();

  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kStockBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) {
      var query = '';

      return StatefulBuilder(
        builder: (context, setSheetState) {
          final normalizedQuery = query.trim().toLowerCase();
          final results = availableProducts.where((product) {
            return normalizedQuery.isEmpty ||
                product.name.toLowerCase().contains(normalizedQuery) ||
                product.sku.toLowerCase().contains(normalizedQuery) ||
                product.barcode.toLowerCase().contains(normalizedQuery);
          }).toList();

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * .78,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 34,
                            height: 4,
                            decoration: BoxDecoration(
                              color: MjasiColors.border,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'stk_search'.tr,
                          style: const TextStyle(
                            color: MjasiColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          autofocus: true,
                          onChanged: (value) {
                            setSheetState(() => query = value);
                          },
                          decoration:
                              stockInput(
                                'stk_search'.tr,
                                icon: Icons.search_rounded,
                              ).copyWith(
                                suffixIcon: IconButton(
                                  tooltip: 'stk_scan'.tr,
                                  icon: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                    size: 20,
                                  ),
                                  onPressed: () async {
                                    final selected = await scanForProduct(
                                      sheetContext,
                                      availableProducts,
                                      trackedOnly: trackedOnly,
                                    );
                                    if (selected != null &&
                                        sheetContext.mounted) {
                                      Navigator.pop(sheetContext, selected);
                                    }
                                  },
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: results.isEmpty
                        ? StockMessage(
                            icon: Icons.inventory_2_outlined,
                            text: 'stk_no_products'.tr,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: results.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, indent: 54),
                            itemBuilder: (context, index) {
                              final product = results[index];

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 5,
                                ),
                                leading: ProductImage(
                                  url: product.imageUrl,
                                  size: 42,
                                  radius: 9,
                                ),
                                title: Text(
                                  product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: MjasiColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${product.sku} · '
                                    '${product.tracked ? '${formatQty(product.quantity)} ${unitLabel(product.unit)}' : 'stk_not_tracked'.tr}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                trailing: StockStateChip(product: product),
                                onTap: () {
                                  Navigator.pop(sheetContext, product);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
