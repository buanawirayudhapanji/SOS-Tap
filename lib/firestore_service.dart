import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Save User to Firestore
  Future<void> createUser(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).set(data);
  }

  // Get User details
  Future<DocumentSnapshot<Map<String, dynamic>>> getUser(String uid) async {
    return await _db.collection('users').doc(uid).get();
  }

  // Update User Profile (Nama, No HP, Email)
  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
  }

  // Create SOS Report
  Future<void> createSOSReport({
    required String userId,
    required String nama,
    required double latitude,
    required double longitude,
  }) async {
    await _db.collection('sos_reports').add({
      'userId': userId,
      'nama': nama,
      'latitude': latitude,
      'longitude': longitude,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Stream of SOS reports ordered by latest first
  Stream<QuerySnapshot<Map<String, dynamic>>> getSOSReportsStream() {
    return _db
        .collection('sos_reports')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Accept/Update SOS Report Status
  Future<void> updateReportStatus(String reportId, String status) async {
    await _db.collection('sos_reports').doc(reportId).update({
      'status': status,
    });
  }

  // Cancel SOS Report
  Future<void> cancelReport(String reportId) async {
    await _db.collection('sos_reports').doc(reportId).update({
      'status': 'cancelled',
    });
  }

  // Stream of all users for Admin
  Stream<QuerySnapshot<Map<String, dynamic>>> getAllUsersStream() {
    return _db.collection('users').snapshots();
  }

  // Toggle User Active Status
  Future<void> updateUserActiveStatus(String uid, bool isActive) async {
    await _db.collection('users').doc(uid).update({
      'isActive': isActive,
    });
  }
}
