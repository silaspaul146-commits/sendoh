import 'i18n.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'design.dart';

class EditProfile extends StatefulWidget {
  const EditProfile({super.key, required this.api, required this.account});
  final SendohApi api;
  final Map<String, dynamic> account;
  @override
  State<EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfile> {
  late final name = TextEditingController(
      text: widget.account['display_name'] as String? ?? '');
  late String? avatar = widget.account['avatar'] as String?;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> photo() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 75);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 200000) {
        throw Exception(t('Choose a photo under 200 KB.'));
      }
      if (mounted) setState(() => avatar = base64Encode(bytes));
    } catch (_) {
      if (mounted) {
        setState(() => error =
            t('Could not load this photo. Choose a smaller JPEG or PNG.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = t('Enter your full name.'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.request('/me/profile', body: {
        'display_name': name.text.trim(),
        'avatar': avatar,
      });
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(result));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(t('Edit profile'),
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800))),
                  IconButton(
                      tooltip: t('Close'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  CircleAvatar(
                      radius: 40,
                      backgroundColor: SendohColors.tealSoft,
                      backgroundImage: avatar == null
                          ? null
                          : MemoryImage(base64Decode(avatar!)),
                      child: avatar == null
                          ? const Icon(Icons.person_outline,
                              size: 38, color: SendohColors.ink)
                          : null),
                  const SizedBox(width: 12),
                  TextButton(
                      onPressed: busy ? null : photo,
                      child: Text(t('Change photo'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700))),
                  if (avatar != null)
                    TextButton(
                        style: TextButton.styleFrom(
                            foregroundColor: SendohColors.secondary),
                        onPressed:
                            busy ? null : () => setState(() => avatar = null),
                        child: Text(t('Remove'))),
                ]),
                const SizedBox(height: 24),
                Text(t('Name'), style: SendohTextStyles.caption),
                const SizedBox(height: 8),
                TextField(
                    controller: name,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [LengthLimitingTextInputFormatter(120)]),
                if (widget.account['username'] != null) ...[
                  const SizedBox(height: 20),
                  Text(t('Username'), style: SendohTextStyles.caption),
                  const SizedBox(height: 8),
                  Semantics(
                      label: t('Your username can’t be changed'),
                      child: Row(children: [
                        Text('@${widget.account['username']}',
                            style: const TextStyle(fontSize: 17)),
                        const SizedBox(width: 10),
                        const Icon(Icons.lock_outline,
                            size: 20, color: SendohColors.secondary),
                      ])),
                ],
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(error!,
                          style: const TextStyle(color: SendohColors.red))),
                const SizedBox(height: 32),
                FilledButton(
                    onPressed: busy ? null : save,
                    child: Text(busy ? t('Saving…') : t('Save changes'))),
              ])));
}

/// Edit profile as a sheet over Profile: photo, name; the username stays.
Future<Map<String, dynamic>?> showEditProfile(BuildContext context,
        {required SendohApi api, required Map<String, dynamic> account}) =>
    showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: SendohColors.canvas,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (_) => EditProfile(api: api, account: account));
