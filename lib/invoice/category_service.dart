import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'category_model.dart';

class CategoryService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static String _uidOrThrow() {
    final u = _auth.currentUser;
    if (u == null) throw StateError('Not signed in');
    return u.uid;
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

  static Future<void> addCategory(CategoryModel category) async {
    await _collectionRef().add(category);
  }

  static Future<void> updateCategory(String id, String name) async {
    await _collectionRef().doc(id).update({'name': name});
  }

  static Future<void> deleteCategory(String id) async {
    await _collectionRef().doc(id).delete();
  }
}
