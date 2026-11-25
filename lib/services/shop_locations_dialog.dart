import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_list/services/branch_service.dart';

class ShopLocationsPage extends StatelessWidget {
  const ShopLocationsPage({super.key});

  Future<void> _openEditor(
    BuildContext context, {
    BusinessBranch? branch,
  }) async {
    final result = await Get.dialog<Map<String, String>>(
      ShopLocationEditorDialog(branch: branch),
      barrierDismissible: false,
    );
    if (result == null) return;
    try {
      if (branch == null) {
        await BranchService.createBranch(
          name: result['name']!,
          location: result['location']!,
        );
      } else {
        await BranchService.updateBranch(
          branchId: branch.id,
          name: result['name']!,
          location: result['location']!,
        );
      }
      Get.snackbar('success'.tr, 'staff_shop_location_saved'.tr);
    } catch (error) {
      final message =
          error is StateError && error.message == 'staff_shop_location_assigned'
          ? 'staff_shop_location_assigned'.tr
          : '$error';
      Get.snackbar('error'.tr, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('staff_shop_locations'.tr),
        leading: IconButton(
          onPressed: Get.back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_business_outlined),
        label: Text('staff_shop_location_add'.tr),
      ),
      body: StreamBuilder<List<BusinessBranch>>(
        stream: BranchService.watchBranches(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final branches = snapshot.data!;
          if (branches.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.storefront_outlined,
                      size: 56,
                      color: Color(0xFF8A9AAF),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'staff_shop_location_empty'.tr,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: branches.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final branch = branches[index];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  leading: const CircleAvatar(
                    child: Icon(Icons.storefront_outlined),
                  ),
                  title: Text(
                    branch.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(branch.location),
                  trailing: IconButton(
                    tooltip: 'edit'.tr,
                    onPressed: () => _openEditor(context, branch: branch),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ShopLocationEditorDialog extends StatefulWidget {
  const ShopLocationEditorDialog({super.key, this.branch});

  final BusinessBranch? branch;

  @override
  State<ShopLocationEditorDialog> createState() =>
      _ShopLocationEditorDialogState();
}

class _ShopLocationEditorDialogState extends State<ShopLocationEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _location;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.branch?.name ?? '');
    _location = TextEditingController(text: widget.branch?.location ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.branch == null ? 'staff_shop_location_add'.tr : 'edit'.tr,
    ),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'staff_shop_location_name'.tr,
                prefixIcon: const Icon(Icons.storefront_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'required_field'.tr
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'staff_shop_location_address'.tr,
                prefixIcon: const Icon(Icons.location_on_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'required_field'.tr
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: Get.back, child: Text('cancel'.tr)),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Get.back<Map<String, String>>(
            result: {
              'name': _name.text.trim(),
              'location': _location.text.trim(),
            },
          );
        },
        child: Text('save'.tr),
      ),
    ],
  );
}
