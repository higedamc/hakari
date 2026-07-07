import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/providers.dart';
import '../../data/signer/amber_signer_service.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/failures/failures.dart';
import '../providers/relay_status_provider.dart';
import '../providers/settings_provider.dart';

/// First-run onboarding: welcome → how it works → connect Amber.
///
/// Login is Amber-only (NIP-55): Hakari never holds a secret key. The
/// last step offers "skip" — everything works offline and login stays
/// available from Settings. Step transitions mirror Wisp's onboarding
/// (fade + slide from the right), themed with Hakari's Material 3 palette.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { welcome, features, connect }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.welcome;
  bool _busy = false;
  String? _error;
  late final Future<bool> _amberInstalled;

  @override
  void initState() {
    super.initState();
    _amberInstalled = const AmberSignerService().isInstalled();
    // Wisp-style: the welcome splash advances by itself.
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted && _step == _Step.welcome) _advance(_Step.features);
    });
  }

  void _advance(_Step next) => setState(() {
    _step = next;
    _error = null;
  });

  Future<void> _loginWithAmber() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pubkey = await ref.read(signerServiceProvider).getPublicKey();
      if (pubkey == null || pubkey.isEmpty) {
        setState(() => _error = 'The signer returned no public key.');
        return;
      }
      final controller = ref.read(settingsProvider.notifier);
      await controller.setSignerMode(SignerMode.amber, pubkeyHex: pubkey);
      final next = await controller.completeOnboarding();
      // Best-effort relay startup; failures surface later in Settings.
      try {
        await ref.read(nostrServiceProvider).initialize(next);
        ref.invalidate(relayStatusProvider);
      } catch (_) {}
    } on Failure catch (f) {
      setState(() => _error = f.message);
    } catch (e) {
      setState(() => _error = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() =>
      ref.read(settingsProvider.notifier).completeOnboarding();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back steps backwards through onboarding instead of leaving the app.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        switch (_step) {
          case _Step.welcome:
            break;
          case _Step.features:
            _advance(_Step.welcome);
          case _Step.connect:
            _advance(_Step.features);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            reverseDuration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1 / 3, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: switch (_step) {
              _Step.welcome => _WelcomeStep(
                key: const ValueKey('welcome'),
                onContinue: () => _advance(_Step.features),
              ),
              _Step.features => _FeaturesStep(
                key: const ValueKey('features'),
                onContinue: () => _advance(_Step.connect),
              ),
              _Step.connect => _ConnectStep(
                key: const ValueKey('connect'),
                amberInstalled: _amberInstalled,
                busy: _busy,
                error: _error,
                onLogin: _loginWithAmber,
                onSkip: _skip,
              ),
            },
          ),
        ),
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark({this.icon = Icons.monitor_weight_outlined});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 48, color: scheme.onPrimaryContainer),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onContinue,
      // Expand so the AnimatedSwitcher's Stack doesn't shrink-wrap the
      // column and pin it to the left edge.
      child: SizedBox.expand(
        child: Column(
          children: [
            const Spacer(flex: 3),
            const _AppMark(),
            const SizedBox(height: 24),
            Text(
              'Hakari',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your weight. Your keys.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(flex: 4),
            Text(
              'Tap to continue',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _FeaturesStep extends StatelessWidget {
  const _FeaturesStep({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(
            'Private by design',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          const _FeatureRow(
            icon: Icons.bluetooth,
            title: 'Bluetooth scales',
            body:
                'Step on a standard BLE scale and your reading '
                'appears instantly.',
          ),
          const SizedBox(height: 24),
          const _FeatureRow(
            icon: Icons.lock_outline,
            title: 'Encrypted backup on Nostr',
            body:
                'Entries are NIP-44 encrypted before they leave the '
                'device — only your key can read them.',
          ),
          const SizedBox(height: 24),
          const _FeatureRow(
            icon: Icons.visibility_off_outlined,
            title: 'No telemetry',
            body: 'No analytics, no trackers. Your data stays yours.',
          ),
          const Spacer(),
          FilledButton(onPressed: onContinue, child: const Text('Continue')),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 24, color: scheme.onSecondaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectStep extends StatelessWidget {
  const _ConnectStep({
    super.key,
    required this.amberInstalled,
    required this.busy,
    required this.error,
    required this.onLogin,
    required this.onSkip,
  });

  final Future<bool> amberInstalled;
  final bool busy;
  final String? error;
  final VoidCallback onLogin;
  final VoidCallback onSkip;

  static final Uri _amberReleases = Uri.parse(
    'https://github.com/greenart7c3/Amber/releases',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          const Center(child: _AppMark(icon: Icons.key_outlined)),
          const SizedBox(height: 24),
          Text(
            'Sign with Amber',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Hakari never holds your Nostr secret key. Amber signs and '
            'encrypts everything in its own app — approve once and '
            "you're set.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (error != null) ...[
            Text(
              error!,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],
          FutureBuilder<bool>(
            future: amberInstalled,
            builder: (context, snapshot) {
              final installed = snapshot.data ?? false;
              if (!snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              if (!installed) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Amber isn't installed on this device.",
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => launchUrl(
                        _amberReleases,
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Get Amber'),
                    ),
                  ],
                );
              }
              return FilledButton.icon(
                onPressed: busy ? null : onLogin,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.key),
                label: Text(busy ? 'Waiting for Amber...' : 'Login with Amber'),
              );
            },
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy ? null : onSkip,
            child: const Text('Skip for now'),
          ),
          Text(
            'You can connect Amber later from Settings.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
