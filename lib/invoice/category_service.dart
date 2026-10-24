import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'category_model.dart';
import 'package:tra_list/services/business_access_service.dart';

class CategoryService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static String _uidOrThrow() {
    if (_auth.currentUser == null) throw StateError('Not signed in');
    return BusinessAccessService.businessId;
  }

  static CollectionReference<CategoryModel> _collectionRef() {
    final uid = _uidOrThrow();
    return _db
        .collection('users')
        .doc(uid)
        .collection('categories')
        .withConverter<CategoryModel>(
          fromFirestore: (snap, _) => CategoryModel.fromFirestore(snap),
          toFirestore: (model, _) => model.toFirestore(),
        );
  }

  static Stream<QuerySnapshot<CategoryModel>> getCategoriesStream() {
    return _collectionRef().orderBy('name').snapshots();
  }

  static Future<QuerySnapshot<CategoryModel>> getCategoriesFromServer() {
    return _collectionRef()
        .orderBy('name')
        .get(const GetOptions(source: Source.server));
  }

  static Future<void> addCategory(CategoryModel category) async {
    if (!BusinessAccessService.can('categories', 'create')) {
      throw StateError('You do not have permission to add categories.');
    }
    final id = category.id;
    if (id == null || id.isEmpty) {
      await _collectionRef().add(category);
    } else {
      await _collectionRef().doc(id).set(category);
    }
  }

  static Future<void> updateCategory(String id, String name) async {
    if (!BusinessAccessService.can('categories', 'edit')) {
      throw StateError('You do not have permission to edit categories.');
    }
    await _collectionRef().doc(id).update({'name': name});
  }

  static Future<void> deleteCategory(String id) async {
    if (!BusinessAccessService.can('categories', 'delete')) {
      throw StateError('You do not have permission to delete categories.');
    }
    await _collectionRef().doc(id).delete();
  }
}
