import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tra_list/jobs/models/job.dart';

class JobService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static String _uidOrThrow() {
    final u = _auth.currentUser;
    if (u == null) throw StateError('Not signed in');
    return u.uid;
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
    // The model generates an ID, so we use `doc(job.id).set(job)`
    await getCollectionRef().doc(job.id).set(job);
  }

  static Future<void> updateJob(String id, Map<String, dynamic> data) async {
    // Ensure updatedAt is always updated
    final updateData = {...data};
    // Do not overwrite createdAt on update
    updateData.remove('createdAt');
    updateData['updatedAt'] = FieldValue.serverTimestamp();
    await getCollectionRef().doc(id).update(data);
  }

  static Future<void> deleteJob(String id) async {
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
