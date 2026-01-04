import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<Map<String, dynamic>> _fetchProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'email': '-'
      };
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      return {
        'email': data['email'] ?? user.email ?? '-',
        'createdAt': data['createdAt'] ?? user.metadata.creationTime,
        'lastLoginAt': data['lastLoginAt'] ?? user.metadata.lastSignInTime,
        'nick': data['nick'],
      };
    } catch (_) {
      return {
        'email': user.email ?? '-',
        'createdAt': user.metadata.creationTime,
        'lastLoginAt': user.metadata.lastSignInTime,
        'nick': null,
      };
    }
  }

  String _formatDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is String) {
      return value;
    }
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchProfile(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? {};
          final email = data['email'] as String? ?? '-';
          final createdAt = _formatDate(data['createdAt']);
          final lastLoginAt = _formatDate(data['lastLoginAt']);
          final nick = data['nick']?.toString();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ListTile(
                title: const Text('Email'),
                subtitle: Text(email),
              ),
              const Divider(),
              ListTile(
                title: const Text('Nick'),
                subtitle: Text(nick?.isNotEmpty == true ? nick! : 'brak'),
              ),
              const Divider(),
              ListTile(
                title: const Text('Utworzono'),
                subtitle: Text(createdAt),
              ),
              const Divider(),
              ListTile(
                title: const Text('Ostatnie logowanie'),
                subtitle: Text(lastLoginAt),
              ),
            ],
          );
        },
      ),
    );
  }
}
