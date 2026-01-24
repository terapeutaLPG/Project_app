import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'services/settings_service.dart';
import 'services/background_location_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>> _profileFuture;
  bool _backgroundSoundsEnabled = false;
  final SettingsService _settingsService = SettingsService();
  final BackgroundLocationService _backgroundLocationService = BackgroundLocationService();

  @override
  void initState() {
    super.initState();
    _profileFuture = _fetchProfile();
    _loadBackgroundSoundsSettings();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadBackgroundSoundsSettings() async {
    final enabled = await _settingsService.isBackgroundSoundsEnabled();
    if (mounted) {
      setState(() {
        _backgroundSoundsEnabled = enabled;
      });
    }
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
        'updatedAt': data['updatedAt'],
        'totalPoints': data['totalPoints'] ?? 0,
        'level': data['level'] ?? 1,
        'nextLevelPoints': data['nextLevelPoints'] ?? 30,
      };
    } catch (_) {
      return {
        'email': user.email ?? '-',
        'createdAt': user.metadata.creationTime,
        'lastLoginAt': user.metadata.lastSignInTime,
        'nick': null,
        'updatedAt': null,
        'totalPoints': 0,
        'level': 1,
        'nextLevelPoints': 30,
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
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pomyślnie zapisano')),
      );
      await _refreshProfile();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'permission-denied'
          ? 'Brak uprawnień w Firestore (rules). Zmień reguły dla users/{uid}.'
          : 'Błąd zapisu: ${e.message ?? e.code}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

  Future<void> _testSound(String label, AndroidSound android, IosSound ios) async {
    try {
      FlutterRingtonePlayer().play(
        android: android,
        ios: ios,
        looping: false,
        volume: 1.0,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Odtwarzanie: $label')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd odtwarzania: $e')),
        );
      }
    }
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
          final totalPoints = data['totalPoints']?.toString() ?? '0';
          final level = data['level']?.toString() ?? '1';
          final nextLevelPoints = data['nextLevelPoints']?.toString() ?? '30';

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
                title: const Text('Poziom'),
                subtitle: Text(level),
              ),
              const Divider(),
              ListTile(
                title: const Text('Punkty'),
                subtitle: Text('$totalPoints / $nextLevelPoints'),
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
              const Divider(),
              ListTile(
                title: const Text('Ostatnia zmiana profilu'),
                subtitle: Text(_formatDate(data['updatedAt'])),
              ),
              const Divider(),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text('Dźwięki w tle'),
                subtitle: const Text('Aplikacja będzie śledzić lokalizację w tle'),
                value: _backgroundSoundsEnabled,
                onChanged: (bool value) async {
                  setState(() {
                    _backgroundSoundsEnabled = value;
                  });
                  await _settingsService.setBackgroundSoundsEnabled(value);
                  
                  if (value) {
                    await _backgroundLocationService.startBackgroundTracking();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Dźwięki w tle włączone'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  } else {
                    _backgroundLocationService.stopBackgroundTracking();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Dźwięki w tle wyłączone'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
              ),
              const Divider(),
              const SizedBox(height: 20),
              const Text(
                'Test dźwięków alertów',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () => _testSound('3 kafelki (~300m)', AndroidSounds.ringtone, IosSounds.electronic),
                icon: const Icon(Icons.notifications),
                label: const Text('Dźwięk: 3 kafelki (~300m)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () => _testSound('2 kafelki (~200m)', AndroidSounds.alarm, IosSounds.glass),
                icon: const Icon(Icons.notifications_active),
                label: const Text('Dźwięk: 2 kafelki (~200m)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () => _testSound('1 kafelek (~100m)', AndroidSounds.notification, IosSounds.triTone),
                icon: const Icon(Icons.notifications_outlined),
                label: const Text('Dźwięk: 1 kafelek (~100m)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
