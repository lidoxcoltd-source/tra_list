import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:tra_list/invoice/add_transaction_controller.dart';
import 'package:tra_list/invoice/transaction_form.dart';
import 'transaction_model.dart';

class AddTransactionPage extends StatefulWidget {
  final TransactionModel? transaction;
  final TransactionType? initialType;

  const AddTransactionPage({super.key, this.transaction, this.initialType});

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  late final AddTransactionController controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Create a unique controller instance for this page.
    // It will be automatically disposed by GetX when the page is popped.
    controller = Get.put(
      AddTransactionController(
        transaction: widget.transaction,
        initialType: widget.initialType,
      ),
      // Use a unique tag to prevent conflicts if multiple forms are open.
      tag: 'transaction_form_${widget.transaction?.id ?? 'new'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.transaction == null;
    const canvas = Color(0xFFF4F7F7);

    return Scaffold(
      backgroundColor: canvas,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 14),
        child: Obx(() {
          final expense = controller.isExpense.value;
          final base = expense
              ? const Color(0xFFB64D4D)
              : const Color(0xFF237A52);
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  base,
                  Color.lerp(base, const Color(0xFF0E2A33), 0.45)!,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 16, 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).canPop()
                          ? Get.back(result: false)
                          : Get.offAllNamed('/'),
                    ),
                    Expanded(
                      child: Text(
                        isNew
                            ? 'add_transaction_title'.tr
                            : 'edit_transaction_title'.tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 19,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        expense
                            ? Icons.north_east_rounded
                            : Icons.south_west_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, c) {
            final form = TransactionForm(
              controller: controller,
              isSaving: _isSaving,
              onSave: (saveAction) async {
                setState(() => _isSaving = true);
                try {
                  await saveAction();
                  if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
                  Get.back(result: true);
                } finally {
                  if (mounted) setState(() => _isSaving = false);
                }
              },
              onCancel: () => Get.back(result: false),
            );
            if (c.maxWidth < 900) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: form,
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(40, 28, 40, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: _buildPreviewPanel()),
                  const SizedBox(width: 32),
                  Expanded(
                    flex: 6,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: form,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    return AnimatedBuilder(
      animation: Listenable.merge([controller.amountC, controller.descC]),
      builder: (context, _) => Obx(() {
        final expense = controller.isExpense.value;
        final color = expense
            ? const Color(0xFFB64D4D)
            : const Color(0xFF237A52);
        final amount = controller.amountC.text.trim();
        final desc = controller.descC.text.trim();
        final category = controller.selectedCategory.value;
        final date = DateFormat(
          'EEE, d MMM yyyy',
        ).format(controller.selectedDate.value);
        Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white70),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        );
        return Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, Color.lerp(color, const Color(0xFF0E2A33), 0.5)!],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    expense
                        ? Icons.north_east_rounded
                        : Icons.south_west_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    (expense ? 'expense' : 'income').tr,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'TZS ${amount.isEmpty ? '0' : amount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Divider(color: Colors.white24),
              row(Icons.notes_rounded, desc.isEmpty ? '—' : desc),
              row(Icons.sell_outlined, category.isEmpty ? '—' : category),
              row(Icons.event_rounded, date),
            ],
          ),
        );
      }),
    );
  }
}
