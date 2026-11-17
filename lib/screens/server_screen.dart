import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/server_status.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/server_provider.dart';
import 'package:lossless_music_download/theme/app_tokens.dart';

class ServerScreen extends ConsumerStatefulWidget {
  const ServerScreen({super.key});

  @override
  ConsumerState<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends ConsumerState<ServerScreen> {
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.read(serverProvider.notifier).refreshStatus();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final serverAsync = ref.watch(serverProvider);
    final startError = ref.watch(serverStartErrorProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.tabServer, style: AppText.pageTitle)),
      body: serverAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => startError != null
            ? const _ServerBody(status: ServerStatus.stopped)
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        error.toString(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        data: (status) => _ServerBody(status: status),
      ),
    );
  }
}

class _ServerBody extends ConsumerWidget {
  const _ServerBody({required this.status});

  final ServerStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = context.tokens;
    final serverAsync = ref.watch(serverProvider);
    final startError = ref.watch(serverStartErrorProvider);
    final bool running = status.running;
    final String? url = status.url;
    final folderPath = ref.watch(downloadDirProvider).value ?? '';

    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpace.page),
      children: [
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: tokens.lineSoft),
          ),
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: running ? cs.primary : tokens.muted2,
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          running ? t.serverRunning : t.serverStopped,
                          style: AppText.section,
                        ),
                        if (status.name != null) ...[
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            status.name!,
                            style: AppText.body.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (running && url != null) ...[
                const SizedBox(height: AppSpace.lg),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  padding: const EdgeInsets.only(
                    left: AppSpace.md,
                    right: AppSpace.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          url,
                          style: AppText.body.merge(tokens.mono),
                        ),
                      ),
                      IconButton(
                        tooltip: t.extensionVerificationCopyLink,
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(t.serverCopied)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
              if (running) ...[
                const SizedBox(height: AppSpace.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.serverFolder,
                      style: AppText.caption.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        folderPath,
                        style: AppText.caption.merge(tokens.mono),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (!running && startError != null) ...[
                const SizedBox(height: AppSpace.lg),
                Card(
                  color: cs.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Text(
                      startError,
                      style: AppText.body.copyWith(color: cs.onErrorContainer),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              FilledButton(
                onPressed: serverAsync.isLoading
                    ? null
                    : () {
                        if (running) {
                          ref.read(serverProvider.notifier).stop();
                        } else {
                          ref.read(serverProvider.notifier).start();
                        }
                      },
                child: serverAsync.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(running ? t.serverStop : t.serverStart),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        Text(
          t.serverConnectFrom,
          style: AppText.caption.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          t.serverHelpDlna,
          style: AppText.body.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          t.serverHint,
          style: AppText.body.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
