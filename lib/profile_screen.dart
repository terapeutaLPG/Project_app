import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _fetchProfile();
  }

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

  Future<void> _refreshProfile() async {
    setState(() {
      _profileFuture = _fetchProfile();
    });
  }

  Future<void> _saveNick(String nick) async {
    final trimmed = nick.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Podaj nick')));
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'nick': trimmed,
          'email': user.email,
          'lastLoginAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pomyślnie zapisano')));
      await _refreshProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Błąd zapisu: $e')));
    }
  }

  Future<void> _showEditNickDialog(String? currentNick) async {
    final controller = TextEditingController(text: currentNick ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edytuj nick'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Nick'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Zapisz'),
            ),
          ],
        );
      },
    );
    if (result != null) {
      await _saveNick(result);
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
        future: _profileFuture,
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
                trailing: TextButton(
                  onPressed: () => _showEditNickDialog(nick),
                  child: const Text('Edytuj'),
                ),
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
