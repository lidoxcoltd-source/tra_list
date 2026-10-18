import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tra_list/jobs/models/job.dart';
import 'package:tra_list/services/business_access_service.dart';

class JobService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static String _uidOrThrow() {
    final u = _auth.currentUser;
    if (u == null) throw StateError('Not signed in');
    return BusinessAccessService.businessId;
  }

  static CollectionReference<Job> getCollectionRef() {
    final uid = _uidOrThrow();
    return _db
        .collection('users')
        .doc(uid)
        .collection('jobs')
        .withConverter<Job>(
          fromFirestore: (snap, _) => Job.fromFirestore(snap),
          toFirestore: (model, _) => model.toFirestore(),
        );
  }

  static Future<void> addJob(Job job) async {
    if (!BusinessAccessService.can('jobs', 'create')) {
      throw StateError('You do not have permission to add jobs.');
    }
    // The model generates an ID, so we use `doc(job.id).set(job)`
    await getCollectionRef().doc(job.id).set(job);
  }

  static Future<void> updateJob(String id, Map<String, dynamic> data) async {
    if (!BusinessAccessService.can('jobs', 'edit')) {
      throw StateError('You do not have permission to edit jobs.');
    }
    // Ensure updatedAt is always updated
    final updateData = {...data};
    // Do not overwrite createdAt on update
    updateData.remove('createdAt');
    updateData['updatedAt'] = FieldValue.serverTimestamp();
    await getCollectionRef().doc(id).update(updateData);
  }

  static Future<void> deleteJob(String id) async {
    if (!BusinessAccessService.can('jobs', 'delete')) {
      throw StateError('You do not have permission to delete jobs.');
    }
    await getCollectionRef().doc(id).delete();
  }

  static Stream<QuerySnapshot<Job>> getJobsStream() {
    return getCollectionRef()
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Example of a specific update
  static Future<void> toggleImportant(String id, bool isImportant) async {
    await updateJob(id, {'isImportant': isImportant});
  }
}
