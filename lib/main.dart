import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

void main() => runApp(const AVaultApp());

class AVaultApp extends StatelessWidget {
  const AVaultApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'A Vault',
      theme: ThemeData.dark(),
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final LocalAuthentication auth = LocalAuthentication();
  final storage = const FlutterSecureStorage();
  final pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    bool canCheck = await auth.canCheckBiometrics;
    if (canCheck) {
      bool didAuth = await auth.authenticate(
        localizedReason: 'افتح A Vault بالبصمة',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (didAuth && mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const VaultScreen()));
      }
    }
  }

  Future<void> _loginWithPin() async {
    String? savedPin = await storage.read(key: 'pin');
    if (savedPin == null) {
      await storage.write(key: 'pin', value: sha256.convert(utf8.encode(pinController.text)).toString());
      _goToVault();
    } else if (savedPin == sha256.convert(utf8.encode(pinController.text)).toString()) {
      _goToVault();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN غلط')));
    }
  }

  void _goToVault() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const VaultScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('A Vault', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN للدخول'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _loginWithPin, child: const Text('دخول')),
            TextButton(onPressed: _tryBiometric, child: const Text('جرب البصمة')),
          ]),
        ),
      ),
    );
  }
}

class VaultService {
  static final storage = const FlutterSecureStorage();
  static encrypt.Key? _key;

  static Future<encrypt.Key> _getKey() async {
    if (_key != null) return _key!;
    String? keyStr = await storage.read(key: 'enc_key');
    if (keyStr == null) {
      _key = encrypt.Key.fromSecureRandom(32);
      await storage.write(key: 'enc_key', value: base64Encode(_key!.bytes));
    } else {
      _key = encrypt.Key(base64Decode(keyStr));
    }
    return _key!;
  }

  static Future<String> _getHiddenDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final hidden = Directory('${dir.path}/.avault');
    if (!await hidden.exists()) await hidden.create();
    return hidden.path;
  }

  static Future<void> encryptAndSave(File file) async {
    final key = await _getKey();
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final bytes = await file.readAsBytes();
    final encrypted = encrypter.encryptBytes(bytes, iv: iv);
    final dir = await _getHiddenDir();
    final newPath = '$dir/${DateTime.now().millisecondsSinceEpoch}.enc';
    File(newPath).writeAsBytesSync(iv.bytes + encrypted.bytes);
  }

  static Future<List<File>> getAllFiles() async {
    final dir = await _getHiddenDir();
    return Directory(dir).listSync().whereType<File>().toList();
  }
}

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final picker = ImagePicker();
  List<File> files = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  void _loadFiles() async {
    files = await VaultService.getAllFiles();
    setState(() {});
  }

  Future<void> _pickAndHide() async {
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await VaultService.encryptAndSave(File(image.path));
      _loadFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('A Vault - المعرض المخفي')),
      body: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
        itemCount: files.length,
        itemBuilder: (_, i) => const Card(child: Icon(Icons.lock, size: 40)), // الصور مشفرة فبنعرض أيقونة قفل
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndHide,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
