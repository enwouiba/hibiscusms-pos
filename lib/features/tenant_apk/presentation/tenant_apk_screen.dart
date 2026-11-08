import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';

class TenantApkInfo {
  final String id;
  final String version;
  final String? packageName;
  final String appName;
  final String status; // pending, building, ready, failed
  final int? fileSize;
  final int downloadCount;
  final DateTime requestedAt;
  final DateTime? builtAt;
  final String? errorMessage;

  TenantApkInfo({
    required this.id,
    required this.version,
    this.packageName,
    required this.appName,
    required this.status,
    this.fileSize,
    required this.downloadCount,
    required this.requestedAt,
    this.builtAt,
    this.errorMessage,
  });

  factory TenantApkInfo.fromJson(Map<String, dynamic> j) {
    int? _i(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }
    DateTime _dt(dynamic v) {
      if (v == null) return DateTime.now();
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }
    DateTime? _dtN(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }
    return TenantApkInfo(
      id: (j['id'] ?? '').toString(),
      version: (j['version'] ?? '1.0.0').toString(),
      packageName: j['package_name']?.toString(),
      appName: (j['app_name'] ?? '').toString(),
      status: (j['status'] ?? 'pending').toString(),
      fileSize: _i(j['file_size']),
      downloadCount: _i(j['download_count']) ?? 0,
      requestedAt: _dt(j['requested_at']),
      builtAt: _dtN(j['built_at']),
      errorMessage: j['error_message']?.toString(),
    );
  }
}

final _apkStatusProvider = FutureProvider.autoDispose<TenantApkInfo?>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final res = await api.dio.get('/api/tenant/mobile-build/status');
    final data = res.data['data'];
    if (data == null) return null;
    return TenantApkInfo.fromJson(data as Map<String, dynamic>);
  } on DioException {
    return null;
  }
});

class TenantApkScreen extends ConsumerWidget {
  const TenantApkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apkAsync = ref.watch(_apkStatusProvider);
    final auth = ref.watch(authControllerProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('APK Pèsonalize'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_apkStatusProvider),
          ),
        ],
      ),
      body: apkAsync.when(
        data: (apk) => _buildContent(context, ref, apk, auth),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erè: $e')),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, TenantApkInfo? apk, AuthSession? auth) {
    if (apk == null) return _emptyState(context, ref);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_statusIcon(apk.status), color: _statusColor(apk.status), size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(apk.appName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          Text('v${apk.version}', style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                    Chip(
                      label: Text(_statusLabel(apk.status), style: const TextStyle(color: Colors.white, fontSize: 11)),
                      backgroundColor: _statusColor(apk.status),
                    ),
                  ],
                ),
                const Divider(),
                _row('Package', apk.packageName ?? '—'),
                _row('Mande', DateFormat('dd MMM yyyy HH:mm').format(apk.requestedAt.toLocal())),
                if (apk.builtAt != null) _row('Bati', DateFormat('dd MMM yyyy HH:mm').format(apk.builtAt!.toLocal())),
                if (apk.fileSize != null) _row('Gwosè', '${(apk.fileSize! / 1024 / 1024).toStringAsFixed(1)} MB'),
                _row('Download', '${apk.downloadCount} fwa'),
                if (apk.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(apk.errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                ],
                const SizedBox(height: 16),
                if (apk.status == 'ready')
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Download APK Mwen'),
                      onPressed: () => _download(context, ref, apk),
                    ),
                  )
                else if (apk.status == 'failed')
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Mande Ankò'),
                      onPressed: () => _request(context, ref),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            apk.status == 'building'
                                ? 'APK ou ap bati kounye a... ap pran ~10 min'
                                : 'APK ou nan keu... ap bati byento',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Info
        Card(
          color: Colors.amber.shade50,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.amber),
                  SizedBox(width: 6),
                  Text('Ki sa ki nan APK pèsonalize ou?', style: TextStyle(fontWeight: FontWeight.bold)),
                ]),
                SizedBox(height: 8),
                Text('• Non biznis ou kòm tit nan launcher\n'
                    '• Logo ou kòm ikon app\n'
                    '• Pwòp package name pou koexistans ak lòt app\n'
                    '• Backend pwòp ou (pos.stann.store)\n'
                    '• Tout fonksyonalite WalCash POS',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.android, size: 80, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'APK pèsonalize',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Mande yon APK ki gen non + logo biznis ou',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 240,
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Mande APK Mwen'),
                onPressed: () => _request(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      );

  Color _statusColor(String s) => switch (s) {
        'ready' => Colors.green,
        'building' => Colors.blue,
        'pending' => Colors.orange,
        'failed' => Colors.red,
        _ => Colors.grey,
      };

  IconData _statusIcon(String s) => switch (s) {
        'ready' => Icons.check_circle,
        'building' => Icons.build,
        'pending' => Icons.hourglass_top,
        'failed' => Icons.error,
        _ => Icons.help,
      };

  String _statusLabel(String s) => switch (s) {
        'ready' => 'PARE',
        'building' => 'AP BATI',
        'pending' => 'AP TANN',
        'failed' => 'ECHWE',
        _ => s.toUpperCase(),
      };

  Future<void> _request(BuildContext context, WidgetRef ref) async {
    final api = ref.read(apiClientProvider);
    try {
      await api.dio.post('/api/tenant/mobile-build/request', data: {});
      ref.invalidate(_apkStatusProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demann soumèt! APK ou ap pare nan ~10 min.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  Future<void> _download(BuildContext context, WidgetRef ref, TenantApkInfo apk) async {
    final tokenStore = ref.read(tokenStoreProvider);
    final token = await tokenStore.read();
    final url = '${AppConstants.apiBaseUrl}/api/tenant/mobile-build/${apk.id}/download';
    final uri = Uri.parse(url);
    // launchUrl ap louvri navigatè ki ap pase token via header. Pou senplisite,
    // m ap pase token nan query (ou ka chanje pou Bearer si endpoint sipòte l).
    if (await canLaunchUrl(uri)) {
      await launchUrl(
        Uri.parse('$url?token=$token'),
        mode: LaunchMode.externalApplication,
      );
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pa kapab louvri: $url')),
        );
      }
    }
  }
}
