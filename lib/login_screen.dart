
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _auth.authStateChanges().listen((user) {
      setState(() {
        _user = user;
      });
    });
  }

  Future<void> _login() async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Wystąpił nieznany błąd")),
      );
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa Eksploracji - Logowanie'),
      ),
      body: Center(
        child: _user != null ? _buildLoggedInView() : _buildLoginForm(),
      ),
    );
  }

  Widget _buildLoggedInView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("Jesteś zalogowany jako ${_user!.email}"),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _logout,
          child: const Text('Wyloguj'),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: 'Hasło'),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _login,
            child: const Text('Zaloguj'),
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RegistrationScreen()),
              );
            },
            child: const Text(
              'Nie masz konta? Zajerestruj je klikajac',
              style: TextStyle(color: Colors.blue),
            ),
          )
        ],
      ),
    );
  }
}
