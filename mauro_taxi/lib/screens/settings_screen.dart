import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _loading = false;
  bool _saved = false;
  String _version = '';

  static const _privacyUrl = 'https://project-jcd2n.vercel.app/privacy-policy';
  static const _contactEmail = 'freire.hector@gmail.com';

  @override
  void initState() {
    super.initState();
    _loadCurrent();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _version = '${info.version} (${info.buildNumber})');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    _nameController.text = prefs.getString('driver_name') ?? '';
    _phoneController.text = prefs.getString('driver_phone') ?? '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('driver_name', _nameController.text.trim());
    await prefs.setString('driver_phone', _phoneController.text.trim());
    setState(() {
      _loading = false;
      _saved = true;
    });
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _openPrivacy() => launchUrl(
        Uri.parse(_privacyUrl),
        mode: LaunchMode.externalApplication,
      );

  Future<void> _openEmail() => launchUrl(
        Uri(scheme: 'mailto', path: _contactEmail),
      );

  Widget _aboutRow({
    required IconData icon,
    required String label,
    String? value,
    VoidCallback? onTap,
    bool showChevron = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF003461)),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF191C1E)),
            ),
            const Spacer(),
            if (value != null)
              Text(
                value,
                style: const TextStyle(fontSize: 14, color: Color(0xFF727781)),
              ),
            if (showChevron) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFF9AA0A6)),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _dec({required String hint, required IconData icon}) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF003461), size: 22),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDDE3EA), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDDE3EA), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF003461), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003461),
        foregroundColor: Colors.white,
        title: const Text(
          'Driver Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Info banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF003461).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFF003461).withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: const Color(0xFF003461).withValues(alpha: 0.7),
                        size: 22),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Your name appears on your passenger\'s map.\nYour phone lets them contact you directly.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF424750),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Name
              const Text('Driver Name',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF191C1E))),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: _dec(hint: 'e.g. John Smith', icon: Icons.person),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Name is required';
                  if (v.trim().length < 2) return 'At least 2 characters';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Phone
              const Text('Phone Number',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF191C1E))),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]'))
                ],
                decoration:
                    _dec(hint: 'e.g. +1 555 123 4567', icon: Icons.phone),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Phone is required';
                  }
                  if (v.trim().length < 7) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 40),

              // About section
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('ABOUT',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Color(0xFF9AA0A6))),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDDE3EA)),
                ),
                child: Column(
                  children: [
                    _aboutRow(
                      icon: Icons.info_outline,
                      label: 'Version',
                      value: _version.isEmpty ? '—' : _version,
                    ),
                    const Divider(height: 1, color: Color(0xFFEEF1F4)),
                    // Privacy Policy (required by Apple App Store guideline 5.1.1)
                    _aboutRow(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Privacy Policy',
                      onTap: _openPrivacy,
                      showChevron: true,
                    ),
                    const Divider(height: 1, color: Color(0xFFEEF1F4)),
                    _aboutRow(
                      icon: Icons.mail_outline,
                      label: 'Contact',
                      value: _contactEmail,
                      onTap: _openEmail,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: _loading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _saved
                        ? const Color(0xFF059669)
                        : const Color(0xFF003461),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_saved ? Icons.check_circle : Icons.save,
                                size: 22),
                            const SizedBox(width: 10),
                            Text(
                              _saved ? 'Saved!' : 'Save Settings',
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
