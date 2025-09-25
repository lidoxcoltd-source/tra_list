import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseTestPage extends StatefulWidget {
  const FirebaseTestPage({super.key});

  @override
  State<FirebaseTestPage> createState() => _FirebaseTestPageState();
}

class _FirebaseTestPageState extends State<FirebaseTestPage> {
  String _status = 'Testing Firebase connection...';
  bool _isConnected = false;
  String _details = '';

  @override
  void initState() {
    super.initState();
    _testFirebaseConnection();
  }

  Future<void> _testFirebaseConnection() async {
    try {
      setState(() {
        _status = 'Checking Firebase initialization...';
        _details = '';
      });

      // Check if Firebase is initialized
      final app = Firebase.app();
      setState(() {
        _details += 'Firebase app name: ${app.name}\n';
        _details += 'Firebase options: ${app.options.projectId}\n';
      });

      // Test Firestore connection
      setState(() {
        _status = 'Testing Firestore connection...';
      });

      final firestore = FirebaseFirestore.instance;

      // Try to read from Firestore
      final testQuery = await firestore
          .collection('receipts')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));

      setState(() {
        _status = 'Firestore connected successfully!';
        _isConnected = true;
        _details += 'Firestore query successful\n';
        _details += 'Collection exists: ${testQuery.docs.isNotEmpty}\n';
        _details += 'Documents found: ${testQuery.docs.length}\n';
      });

      // Try to write a test document
      setState(() {
        _status = 'Testing Firestore write...';
      });

      await firestore
          .collection('test')
          .doc('connection-test')
          .set({'timestamp': FieldValue.serverTimestamp(), 'test': true})
          .timeout(const Duration(seconds: 10));

      setState(() {
        _status = 'Firestore read/write successful!';
        _details += 'Write test successful\n';
      });
    } catch (e) {
      setState(() {
        _status = 'Firebase connection failed';
        _isConnected = false;
        _details += 'Error: $e\n';

        if (e.toString().contains('TimeoutException') ||
            e.toString().contains('Unable to establish connection')) {
          _details += '\n❌ FIRESTORE DATABASE NOT ENABLED\n';
          _details += '\nTo fix this:\n';
          _details += '1. Go to Firebase Console\n';
          _details += '2. Click "Firestore Database" in sidebar\n';
          _details += '3. Click "Create database"\n';
          _details += '4. Choose "Start in test mode"\n';
          _details += '5. Select your preferred location\n';
          _details += '6. Click "Done"\n';
        } else {
          _details += '\nOther possible causes:\n';
          _details += '1. Network connectivity issues\n';
          _details += '2. Security rules blocking access\n';
          _details += '3. Project configuration issues\n';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Connection Test'),
        backgroundColor: const Color(0xFFFFE500),
        foregroundColor: Colors.black87,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isConnected ? Icons.check_circle : Icons.error,
                          color: _isConnected ? Colors.green : Colors.red,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _status,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _isConnected ? Colors.green : Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_details.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Details:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _details,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _testFirebaseConnection,
                icon: const Icon(Icons.refresh),
                label: const Text('Test Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!_isConnected)
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'How to Fix',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '1. Go to Firebase Console\n'
                        '2. Select your project (tra-verify)\n'
                        '3. Click "Firestore Database" in sidebar\n'
                        '4. Click "Create database"\n'
                        '5. Choose "Start in test mode"\n'
                        '6. Select a location\n'
                        '7. Click "Done"',
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          // Open Firebase Console
                        },
                        child: const Text('Open Firebase Console'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
