import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'category_model.dart';
import 'category_service.dart';
import 'transaction_model.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // No tr needed for widgets
        title: const Text('Manage Categories'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<CategoryModel>>(
        stream: CategoryService.getCategoriesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final categories = snapshot.data?.docs ?? [];
          if (categories.isEmpty) {
            return const Center(
              child: Text('No categories found. Tap + to add one.'),
            ); // No tr needed for widgets
          }

          return RefreshIndicator(
            onRefresh: () async {
              // The stream will automatically handle updates, this is for UX
              await Future.delayed(const Duration(seconds: 1));
            },
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index].data();
                final isIncome = category.type == TransactionType.income;
                return ListTile(
                  leading: Icon(
                    isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                    color: isIncome ? Colors.green : Colors.red,
                  ),
                  title: Text(category.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.grey),
                        onPressed: () =>
                            _showCategoryDialog(category: category),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDelete(category),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCategoryDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _confirmDelete(CategoryModel category) {
    Get.dialog(
      AlertDialog(
        title: Text('Delete Category'.tr),
        content: Text('Are you sure you want to delete "${category.name}"?'),
        actions: [
          TextButton(onPressed: Get.back, child: Text('cancel'.tr)),
          TextButton(
            onPressed: () async {
              await CategoryService.deleteCategory(category.id!);
              Get.back(); // No tr needed for logic
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showCategoryDialog({CategoryModel? category}) {
    final nameController = TextEditingController(text: category?.name);
    var type = category?.type ?? TransactionType.expense;

    Get.dialog(
      AlertDialog(
        title: Text(
          category == null ? 'add_category_title'.tr : 'Edit Category'.tr,
        ),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController, // No tr needed for widgets
                  decoration: const InputDecoration(labelText: 'Category Name'),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Type:'.tr),
                    Radio<TransactionType>(
                      value: TransactionType.expense,
                      groupValue: type,
                      onChanged: (v) => setState(() => type = v!),
                    ),
                    Text('expense'.tr),
                    Radio<TransactionType>(
                      value: TransactionType.income,
                      groupValue: type,
                      onChanged: (v) => setState(() => type = v!),
                    ),
                    Text('income'.tr),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: Get.back, child: Text('cancel'.tr)),
          ElevatedButton(
            // No tr needed for widgets
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              final newCategory = CategoryModel(
                id: category?.id,
                name: name,
                type: type,
              );

              if (category == null) {
                await CategoryService.addCategory(newCategory);
              } else {
                await CategoryService.updateCategory(category.id!, name);
              }
              Get.back();
            },
            child: Text('save'.tr),
          ),
        ],
      ),
    );
  }
}
