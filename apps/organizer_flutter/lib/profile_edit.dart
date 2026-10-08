import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';

class EditProfile extends StatefulWidget {
  const EditProfile({super.key, required this.api, required this.account});
  final SendohApi api;
  final Map<String, dynamic> account;
  @override
  State<EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfile> {
  late final name = TextEditingController(text: widget.account['display_name'] as String? ?? '');
  late String? avatar = widget.account['avatar'] as String?;
  bool busy = false;
  String? error;
  @override
  void dispose() { name.dispose(); super.dispose(); }
  Future<void> photo() async {
    setState(() { busy = true; error = null; });
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery,
          maxWidth: 512, maxHeight: 512, imageQuality: 75);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 200000) throw Exception('Choose a photo under 200 KB.');
      if (mounted) setState(() => avatar = base64Encode(bytes));
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load this photo. Choose a smaller JPEG or PNG.');
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Enter your full name.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final result = await widget.api.request('/me/profile', body: {
        'display_name': name.text.trim(), 'avatar': avatar,
      });
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(result));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your profile')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      TextField(controller: name, enabled: !busy, maxLength: 120,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name')),
      if (widget.account['username'] != null)
        ListTile(title: Text('@${widget.account['username']}'),
          subtitle: const Text('Your unique Sendoh username')),
      const SizedBox(height: 20),
      Center(child: CircleAvatar(radius: 42,
        backgroundImage: avatar == null ? null : MemoryImage(base64Decode(avatar!)),
        child: avatar == null ? const Icon(Icons.person_outline, size: 40) : null)),
      TextButton(onPressed: busy ? null : photo, child: const Text('Choose profile photo')),
      if (avatar != null) TextButton(onPressed: busy ? null : () => setState(() => avatar = null),
          child: const Text('Remove photo')),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 24),
      FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Saving…' : 'Save changes')),
    ]));
}
