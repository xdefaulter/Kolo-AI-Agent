import 'dart:convert';
import 'dart:io';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api/provider.dart';
import '../../core/providers_state.dart';
import '../../core/search_settings.dart';
import '../../core/tools/tool_base.dart';
import '../../core/tools/custom_tool_def.dart';
import '../../core/tools/custom_tools_state.dart';
import '../../core/ui/toast.dart';
import '../../core/tools/android/vlm_analyzer.dart';
import '../../core/tools/android/phone_control_mode.dart';
import '../../core/tools/android/scan_phone_apps.dart';
import '../../core/agent/agent_settings.dart';
import '../../core/storage/database.dart';
import '../../core/haptics.dart';
import '../../core/memory/memory_service.dart';
import '../../core/theme_provider.dart';
import '../shared/page_transitions.dart';
import 'local_model_section.dart';
import 'tools_permission_screen.dart';
import '../chat/chat_screen.dart' show toolRegistryProvider;

// ---- Settings Screen ----

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static Widget _sectionHeader(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(providersProvider);
    // 2.4: Reuse existing registry provider instead of calling bootstrapTools()
    final toolCount = ref.watch(toolRegistryProvider).all.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- API Providers ----
          _sectionHeader(
            context,
            'API Providers',
            'Manage your OpenAI-compatible API endpoints. Each can have multiple models.',
          ),
          const SizedBox(height: 8),

          ...providers.map((p) => _ProviderCard(provider: p)),
          const SizedBox(height: 8),

          // Add provider buttons
          Row(
            children: [
              FilledButton.icon(
                onPressed: () =>
                    pushSlideRight(context, const AddProviderScreen()),
                icon: const Icon(Icons.add),
                label: const Text('Add Provider'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _showPresets(context, ref),
                icon: const Icon(Icons.download),
                label: const Text('From Preset'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ---- Local Model (llama.cpp via Termux) ----
          _sectionHeader(
            context,
            'Local Model',
            'Run models on-device with llama.cpp. Installs via apt into '
                'the Termux bootstrap — no cloud round-trip, no API key.',
          ),
          const SizedBox(height: 8),
          const LocalModelSection(),

          const SizedBox(height: 16),

          // ---- Tool Permissions ----
          _sectionHeader(
            context,
            'Tool Permissions',
            'Configure which tools require confirmation.',
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () =>
                pushSlideRight(context, const ToolsPermissionScreen()),
            icon: const Icon(Icons.build_outlined),
            label: Text('Manage $toolCount Tools'),
          ),

          const SizedBox(height: 16),

          // ---- Agent Capabilities (custom tools + skills) ----
          _sectionHeader(
            context,
            'Agent Capabilities',
            'Let the agent author new tools and skills at runtime. '
                'Every creation still requires your approval.',
          ),
          const SizedBox(height: 8),
          const _AgentCapabilitiesSection(),

          const SizedBox(height: 16),

          // ---- Memory ----
          _sectionHeader(
            context,
            'Memory',
            'Long-lived notes the agent uses across chats. '
                'Turn on "Let agent author" to allow the model itself to write memories.',
          ),
          const SizedBox(height: 8),
          const _MemorySection(),

          const SizedBox(height: 16),

          // ---- Vision Model ----
          _sectionHeader(
            context,
            'Vision Model',
            'Configure the model for screen analysis & phone control. Some models (GPT-4o, Gemini) support both text and vision.',
          ),
          const SizedBox(height: 8),
          const _VisionModelSection(),

          const SizedBox(height: 16),

          // ---- Phone Control Mode ----
          _sectionHeader(
            context,
            'Phone Control',
            'Choose how the agent controls the connected phone.',
          ),
          const SizedBox(height: 8),
          const _PhoneControlModeSection(),

          const SizedBox(height: 16),

          // ---- Web Search Provider ----
          _sectionHeader(
            context,
            'Web Search',
            'Choose how the agent searches the web. Jina works without a key; others need a free signup.',
          ),
          const SizedBox(height: 8),
          const _SearchProviderSection(),

          const SizedBox(height: 16),

          // ---- Agent Settings ----
          _sectionHeader(
            context,
            'Agent',
            'Configure how the agent behaves during conversations.',
          ),
          const SizedBox(height: 8),
          _MaxIterationsTile(),

          const SizedBox(height: 16),

          // ---- Data Management ----
          _sectionHeader(
            context,
            'Data',
            'Manage your chat history and app data.',
          ),
          const SizedBox(height: 8),
          _DataCard(
            toolCount: toolCount,
            onClearAllChats: () => _clearAllChats(context),
            onExportChats: () => _exportChats(context),
            onShowAbout: () => _showAbout(context),
            onForceTestCrash: () => _forceTestCrash(context),
          ),

          const SizedBox(height: 16),

          // ---- Input Settings ----
          _sectionHeader(
            context,
            'Input',
            'Customize how you interact with the assistant.',
          ),
          const SizedBox(height: 8),
          const _EnterSendToggle(),

          const SizedBox(height: 16),

          // ---- Appearance ----
          _sectionHeader(
            context,
            'Appearance',
            'Follow the system, or pin to light/dark.',
          ),
          const SizedBox(height: 8),
          const _ThemeModeSection(),
        ],
      ),
    );
  }

  Future<void> _clearAllChats(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Chats?'),
        content: const Text(
          'This will permanently delete all conversations. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      Haptics.medium();
      await AppDatabase.instance.deleteAllChats();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All chats deleted'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _exportChats(BuildContext context) async {
    Haptics.light();
    try {
      final chats = await AppDatabase.instance.getAllChats();
      final allMessages = <Map<String, dynamic>>[];
      for (final chat in chats) {
        final msgs = await AppDatabase.instance.getMessages(chat.id);
        allMessages.add({
          'chat': chat.toMap(),
          'messages': msgs.map((m) => m.toMap()).toList(),
        });
      }
      final json = const JsonEncoder.withIndent('  ').convert(allMessages);
      if (context.mounted) {
        await SharePlus.instance.share(
          ShareParams(text: json, subject: 'Kolo AI Agent - Chat Export'),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _forceTestCrash(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force test crash?'),
        content: const Text(
          'The app will crash immediately. Reopen it to upload the report '
          "to Firebase, then check the Crashlytics dashboard within ~5 minutes. "
          'Only use this on a test build.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Crash now'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Crashlytics.crash() forcibly SIGABRTs the process — the cleanest
    // path to a real native crash report (vs a dart exception).
    FirebaseCrashlytics.instance.crash();
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Kolo AI Agent',
      applicationVersion: '0.1.0',
      applicationIcon: Icon(
        Icons.smart_toy,
        size: 48,
        color: Theme.of(context).colorScheme.primary,
      ),
      children: [
        const Text('Unlimited AI assistant with 50+ tools.'),
        const SizedBox(height: 8),
        const Text('Built with Flutter. Powered by OpenAI-compatible APIs.'),
      ],
    );
  }

  void _showPresets(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Add from Preset',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...ProviderPresets.defaults.map(
              (preset) => ListTile(
                title: Text(preset.name),
                subtitle: Text(
                  preset.baseUrl,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.add_circle_outline),
                onTap: () {
                  ref.read(providersProvider.notifier).addProvider(preset);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Test Connection Chip ──
class _TestConnectionChip extends StatefulWidget {
  final ProviderConfig provider;
  const _TestConnectionChip({required this.provider});
  @override
  State<_TestConnectionChip> createState() => _TestConnectionChipState();
}

class _TestConnectionChipState extends State<_TestConnectionChip> {
  bool _testing = false;
  String? _result;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_testing) {
      return const ActionChip(
        label: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        onPressed: null,
      );
    }
    if (_result != null) {
      final isSuccess = _result == 'ok';
      return ActionChip(
        label: Text(isSuccess ? '✓ Connected' : '✗ Failed'),
        avatar: Icon(
          isSuccess ? Icons.check_circle : Icons.error_outline,
          size: 16,
          color: isSuccess ? Colors.green : cs.error,
        ),
        onPressed: () => setState(() => _result = null),
      );
    }
    return ActionChip(
      label: const Text('Test'),
      avatar: const Icon(Icons.wifi_find, size: 14),
      onPressed: _test,
    );
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final uri = Uri.parse('${widget.provider.baseUrl}/models');
      final request = await client.getUrl(uri);
      if (widget.provider.apiKey.isNotEmpty) {
        request.headers.set(
          'Authorization',
          'Bearer ${widget.provider.apiKey}',
        );
      }
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      client.close();
      if (response.statusCode == 200 || response.statusCode == 401) {
        if (mounted)
          setState(() {
            _testing = false;
            _result = 'ok';
          });
      } else {
        if (mounted)
          setState(() {
            _testing = false;
            _result = 'fail';
          });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _testing = false;
          _result = 'fail';
        });
    }
  }
}

class _ProviderCard extends ConsumerWidget {
  final ProviderConfig provider;
  const _ProviderCard({required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final activeModel = provider.activeModel;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () =>
            pushSlideRight(context, ProviderDetailScreen(provider: provider)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    provider.isActive ? Icons.cloud_done : Icons.cloud_outlined,
                    color: provider.isActive
                        ? Colors.green
                        : cs.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red.withValues(alpha: 0.7),
                    ),
                    tooltip: 'Delete provider',
                    onPressed: () {
                      ref
                          .read(providersProvider.notifier)
                          .removeProvider(provider.id);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                provider.baseUrl,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              if (activeModel != null)
                Text(
                  'Active: ${activeModel.label}',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                Text(
                  'No model selected',
                  style: TextStyle(fontSize: 13, color: cs.error),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(
                      '${provider.models.length} model${provider.models.length == 1 ? '' : 's'}',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (provider.canFetchModels)
                    ActionChip(
                      label: const Text('Fetch'),
                      avatar: const Icon(Icons.refresh, size: 14),
                      onPressed: () async {
                        final count = await ref
                            .read(providersProvider.notifier)
                            .fetchModels(provider.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                count > 0
                                    ? 'Added $count new models'
                                    : 'No new models found',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  if (!provider.isActive)
                    ActionChip(
                      label: const Text('Set Active'),
                      onPressed: () => ref
                          .read(providersProvider.notifier)
                          .setActiveProvider(provider.id),
                    ),
                  _TestConnectionChip(provider: provider),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Provider Detail / Edit Screen ----

class ProviderDetailScreen extends ConsumerStatefulWidget {
  final ProviderConfig provider;
  const ProviderDetailScreen({super.key, required this.provider});

  @override
  ConsumerState<ProviderDetailScreen> createState() =>
      _ProviderDetailScreenState();
}

class _ProviderDetailScreenState extends ConsumerState<ProviderDetailScreen> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  late TextEditingController _keyController;
  late TextEditingController _modelsEndpointController;
  late ProviderConfig _provider;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _provider = widget.provider;
    _nameController = TextEditingController(text: _provider.name);
    _urlController = TextEditingController(text: _provider.baseUrl);
    _keyController = TextEditingController(text: _provider.apiKey);
    _modelsEndpointController = TextEditingController(
      text: _provider.modelsEndpoint ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    _modelsEndpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_provider.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save provider',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Connection Settings ----
          Text('Connection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
              hintText: 'My API Provider',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              border: OutlineInputBorder(),
              hintText: 'https://api.openai.com/v1',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _keyController,
            decoration: InputDecoration(
              labelText: 'API Key',
              border: const OutlineInputBorder(),
              hintText: 'sk-...',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility_off : Icons.visibility,
                ),
                tooltip: _obscureKey ? 'Show API key' : 'Hide API key',
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            obscureText: _obscureKey,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _modelsEndpointController,
            decoration: const InputDecoration(
              labelText: 'Models Endpoint (optional)',
              border: OutlineInputBorder(),
              hintText: 'https://api.openai.com/v1/models',
              helperText: 'Leave empty to use {baseUrl}/models',
            ),
          ),
          const SizedBox(height: 8),
          // Fetch Models button
          if (_provider.canFetchModels)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  final count = await ref
                      .read(providersProvider.notifier)
                      .fetchModels(_provider.id);
                  if (context.mounted) {
                    _refreshProvider();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          count > 0
                              ? 'Added $count new models'
                              : 'No new models found',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Fetch Models'),
              ),
            ),

          const SizedBox(height: 24),

          // ---- Models ----
          Row(
            children: [
              Text(
                'Models (${_provider.models.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add model',
                onPressed: () => _showAddModelDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_provider.models.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.model_training,
                    size: 48,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No models yet',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_provider.canFetchModels)
                    FilledButton.tonal(
                      onPressed: () async {
                        await ref
                            .read(providersProvider.notifier)
                            .fetchModels(_provider.id);
                        _refreshProvider();
                      },
                      child: const Text('Fetch Models'),
                    ),
                  if (!_provider.canFetchModels)
                    FilledButton.tonal(
                      onPressed: () => _showAddModelDialog(context),
                      child: const Text('Add Model Manually'),
                    ),
                ],
              ),
            )
          else
            ..._provider.models.map(
              (model) => _ModelTile(
                model: model,
                isActive: model.modelId == (_provider.activeModel?.modelId),
                onSelect: () {
                  ref
                      .read(providersProvider.notifier)
                      .setActiveModel(_provider.id, model.modelId);
                  _refreshProvider();
                },
                onDelete: () {
                  ref
                      .read(providersProvider.notifier)
                      .removeModel(_provider.id, model.modelId);
                  _refreshProvider();
                },
              ),
            ),

          const SizedBox(height: 24),

          // ---- Tool Access (per-provider) ----
          Text('Tool Access', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Restrict which tools this provider can call. Smaller local '
            'models often fail to format complex tool schemas; the preset '
            'below hides risky tools automatically without affecting other '
            'providers.',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _provider.smallModelMode,
            title: const Text('Small-model safety'),
            subtitle: const Text(
              'Auto-hide dangerous + multi-step tools for this provider.',
            ),
            onChanged: (v) {
              final updated = _provider.copyWith(smallModelMode: v);
              ref.read(providersProvider.notifier).updateProvider(updated);
              setState(() => _provider = updated);
            },
          ),
          ListTile(
            leading: const Icon(Icons.block_outlined),
            title: Text(
              'Disabled tools'
              '${_provider.disabledTools.isEmpty ? '' : ' (${_provider.disabledTools.length})'}',
            ),
            subtitle: const Text('Tap to pick specific tools to hide.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editDisabledTools(context),
          ),
        ],
      ),
    );
  }

  /// Full-list picker for per-provider tool blocklist. Lets the user
  /// toggle individual tools on/off. Doesn't touch the global
  /// permission manager — this is a provider-scoped filter only.
  Future<void> _editDisabledTools(BuildContext context) async {
    final registry = ref.read(toolRegistryProvider);
    final allTools = registry.all.map((t) => t.name).toList()..sort();
    final selected = {..._provider.disabledTools};
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (ctx, scroll) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Block tools for ${_provider.name}',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  itemCount: allTools.length,
                  itemBuilder: (ctx, i) {
                    final name = allTools[i];
                    return CheckboxListTile(
                      title: Text(
                        name,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                      value: selected.contains(name),
                      dense: true,
                      onChanged: (v) => setSheetState(() {
                        if (v == true) {
                          selected.add(name);
                        } else {
                          selected.remove(name);
                        }
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final updated = _provider.copyWith(disabledTools: selected);
    ref.read(providersProvider.notifier).updateProvider(updated);
    setState(() => _provider = updated);
  }

  void _refreshProvider() {
    final providers = ref.read(providersProvider);
    final updated = providers.where((p) => p.id == _provider.id).firstOrNull;
    if (updated != null) {
      setState(() {
        _provider = updated;
      });
    }
  }

  void _save() {
    final updated = _provider.copyWith(
      name: _nameController.text.trim(),
      baseUrl: _urlController.text.trim(),
      apiKey: _keyController.text.trim(),
      modelsEndpoint: _modelsEndpointController.text.trim().isEmpty
          ? null
          : _modelsEndpointController.text.trim(),
    );
    ref.read(providersProvider.notifier).updateProvider(updated);
    setState(() => _provider = updated);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Provider saved')));
  }

  void _showAddModelDialog(BuildContext context) {
    final modelIdController = TextEditingController();
    final displayNameController = TextEditingController();
    final maxTokensController = TextEditingController(text: '4096');

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Model'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: modelIdController,
              decoration: const InputDecoration(
                labelText: 'Model ID *',
                hintText: 'gpt-4o, llama3.2, etc.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: displayNameController,
              decoration: const InputDecoration(
                labelText: 'Display Name (optional)',
                hintText: 'GPT-4o',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: maxTokensController,
              decoration: const InputDecoration(
                labelText: 'Max Tokens',
                hintText: '4096',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (modelIdController.text.trim().isEmpty) return;
              final model = ModelConfig(
                modelId: modelIdController.text.trim(),
                displayName: displayNameController.text.trim().isEmpty
                    ? null
                    : displayNameController.text.trim(),
                maxTokens: int.tryParse(maxTokensController.text) ?? 4096,
                isCustom: true,
              );
              ref
                  .read(providersProvider.notifier)
                  .addModel(_provider.id, model);
              _refreshProvider();
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ).whenComplete(() {
      // Dispose all three controllers regardless of how the dialog closed
      // (Add, Cancel, or barrier dismiss). Prevents leaking them on
      // repeated dialog opens.
      modelIdController.dispose();
      displayNameController.dispose();
      maxTokensController.dispose();
    });
  }
}

class _ModelTile extends StatelessWidget {
  final ModelConfig model;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  const _ModelTile({
    required this.model,
    required this.isActive,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(
        isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: isActive ? cs.primary : cs.onSurface.withValues(alpha: 0.4),
      ),
      title: Text(
        model.label,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        [
          model.modelId,
          if (model.contextWindow != null)
            '${(model.contextWindow! / 1000).round()}k ctx',
          '${model.maxTokens} tok',
          if (model.isCustom) 'custom',
        ].join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18),
        tooltip: 'Remove model',
        onPressed: onDelete,
      ),
      selected: isActive,
      onTap: onSelect,
    );
  }
}

// ---- Add Provider Screen ----

class AddProviderScreen extends ConsumerStatefulWidget {
  const AddProviderScreen({super.key});
  @override
  ConsumerState<AddProviderScreen> createState() => _AddProviderScreenState();
}

class _AddProviderScreenState extends ConsumerState<AddProviderScreen> {
  final _nameController = TextEditingController(text: 'My Provider');
  final _urlController = TextEditingController(
    text: 'https://api.openai.com/v1',
  );
  final _keyController = TextEditingController();
  final _modelsEndpointController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    _modelsEndpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add API Provider')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Create a new OpenAI-compatible API connection.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name *',
              border: OutlineInputBorder(),
              hintText: 'My Provider',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Base URL *',
              border: OutlineInputBorder(),
              hintText: 'https://api.openai.com/v1',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _keyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              border: OutlineInputBorder(),
              hintText: 'sk-...',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _modelsEndpointController,
            decoration: const InputDecoration(
              labelText: 'Models Endpoint (optional)',
              border: OutlineInputBorder(),
              hintText: 'https://api.openai.com/v1/models',
              helperText: 'Leave empty to use {baseUrl}/models',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              if (_nameController.text.trim().isEmpty ||
                  _urlController.text.trim().isEmpty)
                return;
              final provider = ProviderConfig(
                name: _nameController.text.trim(),
                baseUrl: _urlController.text.trim(),
                apiKey: _keyController.text.trim(),
                modelsEndpoint: _modelsEndpointController.text.trim().isEmpty
                    ? null
                    : _modelsEndpointController.text.trim(),
              );
              ref.read(providersProvider.notifier).addProvider(provider);
              Navigator.pop(context);
            },
            child: const Text('Create Provider'),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Or start from a preset:',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...ProviderPresets.defaults.map(
            (preset) => ListTile(
              title: Text(preset.name),
              subtitle: Text(
                preset.baseUrl,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.add),
              onTap: () {
                ref.read(providersProvider.notifier).addProvider(preset);
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vision Model Section ──

class _VisionModelSection extends ConsumerWidget {
  const _VisionModelSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visionConfig = ref.watch(visionModelConfigProvider);
    final providers = ref.watch(providersProvider);
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Same model / Separate model toggle
            SegmentedButton<VisionModelMode>(
              segments: const [
                ButtonSegment(
                  value: VisionModelMode.sameAsChat,
                  label: Text('Same as Chat'),
                  icon: Icon(Icons.link, size: 16),
                ),
                ButtonSegment(
                  value: VisionModelMode.separate,
                  label: Text('Different Model'),
                  icon: Icon(Icons.visibility, size: 16),
                ),
              ],
              selected: {visionConfig.mode},
              onSelectionChanged: (modes) {
                ref
                    .read(visionModelConfigProvider.notifier)
                    .update(
                      VisionModelConfig(
                        mode: modes.first,
                        providerId: visionConfig.providerId,
                        modelId: visionConfig.modelId,
                      ),
                    );
              },
            ),

            const SizedBox(height: 12),

            if (visionConfig.mode == VisionModelMode.sameAsChat) ...[
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Using the same chat model for vision. Make sure it supports image input (e.g. GPT-4o, Gemini, Claude).',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            if (visionConfig.mode == VisionModelMode.separate) ...[
              Text(
                'Select Vision Provider & Model',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),

              // Provider dropdown
              DropdownButtonFormField<String>(
                initialValue: visionConfig.providerId,
                decoration: const InputDecoration(
                  labelText: 'Vision Provider',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: providers
                    .map(
                      (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                    )
                    .toList(),
                onChanged: (id) {
                  ref
                      .read(visionModelConfigProvider.notifier)
                      .update(
                        VisionModelConfig(
                          mode: VisionModelMode.separate,
                          providerId: id,
                          modelId: null,
                        ),
                      );
                },
              ),

              const SizedBox(height: 12),

              // Model dropdown (for selected provider)
              if (visionConfig.providerId != null)
                Builder(
                  builder: (context) {
                    final provider = providers
                        .where((p) => p.id == visionConfig.providerId)
                        .firstOrNull;
                    if (provider == null) return const SizedBox.shrink();
                    return DropdownButtonFormField<String>(
                      initialValue:
                          visionConfig.modelId != null &&
                              provider.models.any(
                                (m) => m.modelId == visionConfig.modelId,
                              )
                          ? visionConfig.modelId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Vision Model',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: provider.models
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.modelId,
                              child: Text(m.label),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        ref
                            .read(visionModelConfigProvider.notifier)
                            .update(
                              VisionModelConfig(
                                mode: VisionModelMode.separate,
                                providerId: visionConfig.providerId,
                                modelId: id,
                              ),
                            );
                      },
                    );
                  },
                ),

              const SizedBox(height: 8),
              Text(
                'Tip: Use a model with vision capabilities — GPT-4o, Gemini 2.5 Pro, Claude Sonnet, etc.',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Phone Control Mode Section ──

class _PhoneControlModeSection extends ConsumerStatefulWidget {
  const _PhoneControlModeSection();
  @override
  ConsumerState<_PhoneControlModeSection> createState() =>
      _PhoneControlModeSectionState();
}

class _PhoneControlModeSectionState
    extends ConsumerState<_PhoneControlModeSection> {
  bool _scanning = false;
  String? _scanResult;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(phoneControlModeProvider);
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phonelink, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Control Mode',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Accessibility uses the built-in service. ADB uses shell commands over USB/Wi-Fi debug connection.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<PhoneControlMode>(
              segments: const [
                ButtonSegment(
                  value: PhoneControlMode.accessibility,
                  label: Text('Accessibility'),
                  icon: Icon(Icons.accessibility_new, size: 16),
                ),
                ButtonSegment(
                  value: PhoneControlMode.adb,
                  label: Text('ADB'),
                  icon: Icon(Icons.usb, size: 16),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (modes) {
                Haptics.selection();
                ref.read(phoneControlModeProvider.notifier).update(modes.first);
              },
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Scan Phone Apps button
            Row(
              children: [
                Icon(Icons.app_registration, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'App Scanner',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Scan installed apps via ADB to discover intents, deep links, and exported components. '
              'Results are saved and injected into AI context.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            if (_scanning)
              const Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Scanning apps... this may take a minute.'),
                  ),
                ],
              )
            else
              FilledButton.tonalIcon(
                onPressed: _scanApps,
                icon: const Icon(Icons.radar),
                label: const Text('Scan Phone Apps'),
              ),
            if (_scanResult != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _scanResult!,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _scanApps() async {
    setState(() {
      _scanning = true;
      _scanResult = null;
    });
    try {
      final tool = ScanPhoneAppsTool();
      final result = await tool.execute(
        {},
        ToolContext(chatId: 'settings', permissionChecker: (_) async => true),
      );
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanResult = result.success
              ? result.output
              : 'Error: ${result.error}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanResult = 'Scan failed: $e';
        });
      }
    }
  }
}

// ── Max Iterations Tile ──

class _MaxIterationsTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MaxIterationsTile> createState() => _MaxIterationsTileState();
}

class _MaxIterationsTileState extends ConsumerState<_MaxIterationsTile> {
  late TextEditingController _controller;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxIter = ref.watch(maxIterationsProvider);
    final cs = Theme.of(context).colorScheme;

    if (!_loaded) {
      _controller.text = maxIter.toString();
      _loaded = true;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.repeat, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Max Iterations',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  '$maxIter',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Maximum number of think-act-observe cycles per message. Higher = longer tasks, lower = faster but may not finish complex tasks.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            Slider(
              value: maxIter.toDouble(),
              min: 5,
              max: 100,
              divisions: 19,
              label: maxIter.toString(),
              onChanged: (value) {
                final v = value.round();
                ref.read(maxIterationsProvider.notifier).state = v;
                _controller.text = v.toString();
                AppDatabase.instance.saveSetting(
                  'max_iterations',
                  v.toString(),
                );
              },
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '5 (quick)',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                Text(
                  '100 (deep)',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Enter = Send Toggle ──
class _EnterSendToggle extends ConsumerStatefulWidget {
  const _EnterSendToggle();
  @override
  ConsumerState<_EnterSendToggle> createState() => _EnterSendToggleState();
}

class _EnterSendToggleState extends ConsumerState<_EnterSendToggle> {
  bool _enterToSend = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final val = await AppDatabase.instance.getSetting('enter_to_send');
    if (mounted) {
      setState(() {
        _enterToSend = val == 'true';
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_loaded) return const SizedBox.shrink();
    return Card(
      child: SwitchListTile(
        secondary: Icon(Icons.keyboard_return, color: cs.primary),
        title: const Text('Enter = Send'),
        subtitle: Text(
          _enterToSend ? 'Enter sends the message' : 'Enter creates a new line',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
        value: _enterToSend,
        onChanged: (val) {
          Haptics.selection();
          setState(() => _enterToSend = val);
          AppDatabase.instance.saveSetting('enter_to_send', val.toString());
        },
      ),
    );
  }
}

/// Search provider picker + per-provider API key input. Mirrors the style of
/// the cloud-provider section: a card per backend, selected one is highlighted,
/// and providers that need a key get an inline obscured text field.
class _SearchProviderSection extends ConsumerStatefulWidget {
  const _SearchProviderSection();

  @override
  ConsumerState<_SearchProviderSection> createState() =>
      _SearchProviderSectionState();
}

class _SearchProviderSectionState
    extends ConsumerState<_SearchProviderSection> {
  final Map<SearchProvider, TextEditingController> _keyControllers = {};
  final Map<SearchProvider, bool> _obscure = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    for (final p in SearchProvider.values) {
      final settingKey = p.apiKeySettingKey;
      if (settingKey == null) continue;
      final v = await AppDatabase.instance.getSetting(settingKey);
      _keyControllers[p] = TextEditingController(text: v ?? '');
      _obscure[p] = true;
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveKey(SearchProvider p) async {
    final key = p.apiKeySettingKey;
    if (key == null) return;
    final value = _keyControllers[p]?.text.trim() ?? '';
    await AppDatabase.instance.saveSetting(key, value);
    if (!mounted) return;
    showKoloToast(
      context,
      value.isEmpty ? 'Cleared ${p.label} key' : 'Saved ${p.label} key',
      kind: value.isEmpty ? ToastKind.info : ToastKind.success,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final selected = ref.watch(searchProviderConfigProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: SearchProvider.values
          .map(
            (p) => _SearchProviderCard(
              provider: p,
              isSelected: p == selected,
              cs: cs,
              keyController: _keyControllers[p],
              obscure: _obscure[p] ?? true,
              onToggleObscure: () => setState(() {
                _obscure[p] = !(_obscure[p] ?? true);
              }),
              onSelect: () {
                Haptics.selection();
                ref.read(searchProviderConfigProvider.notifier).set(p);
              },
              onSaveKey: () => _saveKey(p),
            ),
          )
          .toList(),
    );
  }
}

class _SearchProviderCard extends StatelessWidget {
  final SearchProvider provider;
  final bool isSelected;
  final ColorScheme cs;
  final TextEditingController? keyController;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onSelect;
  final VoidCallback onSaveKey;

  const _SearchProviderCard({
    required this.provider,
    required this.isSelected,
    required this.cs,
    required this.keyController,
    required this.obscure,
    required this.onToggleObscure,
    required this.onSelect,
    required this.onSaveKey,
  });

  @override
  Widget build(BuildContext context) {
    final needsKey = provider.requiresKey;
    final hasKey = (keyController?.text.trim().isNotEmpty) ?? false;
    final Color statusColor = isSelected
        ? cs.primary
        : cs.onSurface.withValues(alpha: 0.5);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: cs.primary, width: 1.5)
            : BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: statusColor,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (needsKey)
                    Chip(
                      label: Text(hasKey ? 'Key set' : 'No key'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: hasKey
                          ? Colors.green.withValues(alpha: 0.15)
                          : cs.errorContainer.withValues(alpha: 0.5),
                      side: BorderSide.none,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: hasKey
                            ? Colors.green.shade700
                            : cs.onErrorContainer,
                      ),
                    )
                  else
                    Chip(
                      label: const Text('No key needed'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: cs.surfaceContainerHighest,
                      side: BorderSide.none,
                      labelStyle: const TextStyle(fontSize: 11),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  provider.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              if (keyController != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: keyController,
                          obscureText: obscure,
                          decoration: InputDecoration(
                            labelText: needsKey
                                ? 'API Key (required)'
                                : 'API Key (optional)',
                            isDense: true,
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 18,
                              ),
                              tooltip: obscure ? 'Show key' : 'Hide key',
                              onPressed: onToggleObscure,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: onSaveKey,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings section that exposes the two Agent Capability toggles
/// (custom tools, skills) plus a link to manage existing custom tools.
/// Bound to [agentCanCreateToolsProvider] and [skillsEnabledProvider]
/// so flipping the toggle immediately reconfigures the tool registry.
class _AgentCapabilitiesSection extends ConsumerWidget {
  const _AgentCapabilitiesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final canCreate = ref.watch(agentCanCreateToolsProvider);
    final skillsOn = ref.watch(skillsEnabledProvider);
    final customTools = ref.watch(customToolsProvider);
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(Icons.build_circle_outlined, color: cs.primary),
            title: const Text('Custom Tools'),
            subtitle: const Text(
              'Let the agent author prompt or composed tools at runtime. '
              'Every creation requires your approval. Off by default.',
              style: TextStyle(fontSize: 12),
            ),
            value: canCreate,
            onChanged: (v) {
              Haptics.selection();
              ref.read(agentCanCreateToolsProvider.notifier).set(v);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: Icon(Icons.auto_stories_outlined, color: cs.primary),
            title: const Text('Skills'),
            subtitle: const Text(
              'Let the agent author and read SKILL.md playbooks.',
              style: TextStyle(fontSize: 12),
            ),
            value: skillsOn,
            onChanged: (v) {
              Haptics.selection();
              ref.read(skillsEnabledProvider.notifier).set(v);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.view_list_outlined, color: cs.primary),
            title: const Text('Manage Custom Tools'),
            subtitle: Text(
              customTools.isEmpty
                  ? 'No custom tools saved yet'
                  : '${customTools.length} saved',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                pushSlideRight(context, const _ManageCustomToolsScreen()),
          ),
        ],
      ),
    );
  }
}

/// Lists saved custom-tool definitions and lets the user delete them.
/// Edit lives with the agent (via the `create_tool` meta-tool) —
/// re-authoring with the same name overwrites.
class _ManageCustomToolsScreen extends ConsumerWidget {
  const _ManageCustomToolsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tools = ref.watch(customToolsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Custom Tools')),
      body: tools.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.build_outlined,
                      size: 40,
                      color: cs.onSurface.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No custom tools yet',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'With "Custom Tools" enabled in Settings, the agent can '
                      'author tools by calling its `create_tool` meta-tool.',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: tools.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final t = tools[i];
                return ListTile(
                  onTap: () =>
                      pushSlideRight(context, _EditCustomToolScreen(tool: t)),
                  leading: CircleAvatar(
                    backgroundColor: _permColor(
                      t.permission,
                    ).withValues(alpha: 0.15),
                    child: Icon(
                      _iconForKind(t.kind),
                      color: _permColor(t.permission),
                      size: 18,
                    ),
                  ),
                  title: Text(
                    t.name,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  subtitle: Text(
                    '${t.kind.wireName} · ${t.permission.name} · ${t.description}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDelete(context, ref, t),
                  ),
                );
              },
            ),
    );
  }

  IconData _iconForKind(CustomToolKind kind) {
    switch (kind) {
      case CustomToolKind.shell:
        return Icons.terminal;
      case CustomToolKind.prompt:
        return Icons.chat_bubble_outline;
      case CustomToolKind.composed:
        return Icons.account_tree_outlined;
    }
  }

  Color _permColor(ToolPermission p) {
    switch (p) {
      case ToolPermission.safe:
        return Colors.green;
      case ToolPermission.sensitive:
        return Colors.orange;
      case ToolPermission.dangerous:
        return Colors.red;
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CustomToolDef t,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${t.name}"?'),
        content: const Text(
          'The agent will no longer be able to call this tool. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AppDatabase.instance.deleteCustomTool(t.id);
      await ref.read(customToolsProvider.notifier).reload();
      if (context.mounted) {
        showKoloToast(context, 'Deleted ${t.name}', kind: ToastKind.success);
      }
    }
  }
}

/// Editor for an existing custom tool. Deliberately minimal — the user
/// can change **description** + **permission**. The agent-visible name,
/// JSON schema, and the
/// implementation body are intentionally read-only from the UI; editing
/// those is the agent's job via the `create_tool` meta-tool (same name
/// overwrites), keeping structural changes auditable through the
/// permission-prompt flow.
class _EditCustomToolScreen extends ConsumerStatefulWidget {
  final CustomToolDef tool;
  const _EditCustomToolScreen({required this.tool});

  @override
  ConsumerState<_EditCustomToolScreen> createState() =>
      _EditCustomToolScreenState();
}

class _EditCustomToolScreenState extends ConsumerState<_EditCustomToolScreen> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _timeoutCtrl;
  late ToolPermission _permission;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.tool.description);
    _timeoutCtrl = TextEditingController(
      text: '${widget.tool.implementation['timeoutSec'] ?? 60}',
    );
    _permission = widget.tool.permission;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _timeoutCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newDesc = _descCtrl.text.trim();
    if (newDesc.length < 10) {
      showKoloToast(
        context,
        'Description must be at least 10 characters',
        kind: ToastKind.warning,
      );
      return;
    }
    setState(() => _saving = true);

    Map<String, dynamic>? newImpl;
    if (widget.tool.kind == CustomToolKind.shell) {
      final timeout = int.tryParse(_timeoutCtrl.text.trim());
      if (timeout == null || timeout <= 0) {
        showKoloToast(
          context,
          'Timeout must be a positive integer (seconds)',
          kind: ToastKind.warning,
        );
        setState(() => _saving = false);
        return;
      }
      newImpl = {...widget.tool.implementation, 'timeoutSec': timeout};
    }

    final updated = widget.tool.copyWith(
      description: newDesc,
      permission: _permission,
      implementation: newImpl,
    );

    try {
      await AppDatabase.instance.saveCustomTool(updated);
      await ref.read(customToolsProvider.notifier).reload();
      if (!mounted) return;
      showKoloToast(context, 'Saved ${updated.name}', kind: ToastKind.success);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showKoloToast(context, 'Save failed: $e', kind: ToastKind.error);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = widget.tool;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.name, style: const TextStyle(fontFamily: 'monospace')),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            tooltip: 'Save',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Static summary — these fields are only editable via the agent.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_kindIcon(t.kind), size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(
                      '${t.kind.wireName} kind',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  t.kind == CustomToolKind.shell
                      ? 'Legacy shell tools are disabled in this chat build.'
                      : 'Name and implementation can only be changed by the agent '
                            'via `create_tool` with the same name.',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Description', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          TextField(
            controller: _descCtrl,
            maxLines: null,
            minLines: 2,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'What the tool does + when to use it',
            ),
          ),
          const SizedBox(height: 20),
          Text('Permission', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<ToolPermission>(
            segments: const [
              ButtonSegment(
                value: ToolPermission.safe,
                label: Text('Safe'),
                icon: Icon(Icons.check_circle_outline, size: 16),
              ),
              ButtonSegment(
                value: ToolPermission.sensitive,
                label: Text('Sensitive'),
                icon: Icon(Icons.warning_amber_outlined, size: 16),
              ),
              ButtonSegment(
                value: ToolPermission.dangerous,
                label: Text('Dangerous'),
                icon: Icon(Icons.dangerous_outlined, size: 16),
              ),
            ],
            selected: {_permission},
            onSelectionChanged: (s) {
              setState(() => _permission = s.first);
              Haptics.selection();
            },
          ),
          const SizedBox(height: 8),
          Text(
            _permissionBlurb(_permission),
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (t.kind == CustomToolKind.shell) ...[
            const SizedBox(height: 20),
            Text(
              'Timeout (seconds)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _timeoutCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                suffixText: 'seconds',
              ),
            ),
          ],
          const SizedBox(height: 24),
          // Read-only implementation preview for context.
          Text(
            'Implementation (read-only)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(t.implementation),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  IconData _kindIcon(CustomToolKind kind) {
    switch (kind) {
      case CustomToolKind.shell:
        return Icons.terminal;
      case CustomToolKind.prompt:
        return Icons.chat_bubble_outline;
      case CustomToolKind.composed:
        return Icons.account_tree_outlined;
    }
  }

  String _permissionBlurb(ToolPermission p) {
    switch (p) {
      case ToolPermission.safe:
        return 'Auto-approved. Use for read-only, side-effect-free tools.';
      case ToolPermission.sensitive:
        return 'Prompts on every use. Use when personal data or state changes.';
      case ToolPermission.dangerous:
        return 'Prompts on every use, with warning. Destructive or irreversible.';
    }
  }
}

/// Data-management card with a hidden Crashlytics test-crash row.
/// Following the Android convention, the crash row is revealed after
/// seven taps on the About tile — casual users never see it.
class _DataCard extends StatefulWidget {
  final int toolCount;
  final VoidCallback onClearAllChats;
  final VoidCallback onExportChats;
  final VoidCallback onShowAbout;
  final VoidCallback onForceTestCrash;

  const _DataCard({
    required this.toolCount,
    required this.onClearAllChats,
    required this.onExportChats,
    required this.onShowAbout,
    required this.onForceTestCrash,
  });

  @override
  State<_DataCard> createState() => _DataCardState();
}

class _DataCardState extends State<_DataCard> {
  int _aboutTaps = 0;
  bool _devRevealed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear All Chats'),
            subtitle: const Text('Delete all conversations permanently'),
            onTap: widget.onClearAllChats,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Export Chat History'),
            subtitle: const Text('Share all chats as JSON'),
            onTap: widget.onExportChats,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: Text(
              'v0.1.0 · ${widget.toolCount} tools'
              '${_devRevealed ? " · Developer mode on" : ""}',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            onTap: () {
              setState(() {
                _aboutTaps++;
                if (_aboutTaps >= 7 && !_devRevealed) {
                  _devRevealed = true;
                  Haptics.medium();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Developer options unlocked.'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              });
              widget.onShowAbout();
            },
          ),
          if (_devRevealed) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.bug_report_outlined,
                color: Colors.orange,
              ),
              title: const Text('Force test crash'),
              subtitle: const Text(
                'Crashes the app to verify Crashlytics delivery.',
              ),
              onTap: widget.onForceTestCrash,
            ),
          ],
        ],
      ),
    );
  }
}

class _MemorySection extends ConsumerWidget {
  const _MemorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recallEnabled = ref.watch(memoryRecallEnabledProvider);
    final canAuthor = ref.watch(agentCanCreateMemoriesProvider);
    final memories = ref.watch(memoriesProvider);
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            value: recallEnabled,
            onChanged: (v) {
              Haptics.light();
              ref.read(memoryRecallEnabledProvider.notifier).set(v);
            },
            title: const Text('Use memories in chat'),
            subtitle: const Text(
              'Inject relevant saved memories into the system prompt each turn.',
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: canAuthor,
            onChanged: (v) {
              Haptics.light();
              ref.read(agentCanCreateMemoriesProvider.notifier).set(v);
            },
            title: const Text('Let agent author memories'),
            subtitle: const Text(
              'Registers remember_this + forget_memory tools. '
              'Every save still prompts for approval.',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.psychology_outlined),
            title: Text('Manage memories (${memories.length})'),
            subtitle: const Text('Review, edit, or delete saved memories.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => pushSlideRight(context, const _ManageMemoriesScreen()),
          ),
        ],
      ),
    );
  }
}

class _ManageMemoriesScreen extends ConsumerStatefulWidget {
  const _ManageMemoriesScreen();

  @override
  ConsumerState<_ManageMemoriesScreen> createState() =>
      _ManageMemoriesScreenState();
}

class _ManageMemoriesScreenState extends ConsumerState<_ManageMemoriesScreen> {
  @override
  Widget build(BuildContext context) {
    final memories = ref.watch(memoriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add memory',
            onPressed: () => _addMemory(context),
          ),
          if (memories.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Delete all',
              onPressed: () => _deleteAll(context),
            ),
        ],
      ),
      body: memories.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No memories yet.\nUse the + button to add one, or enable '
                  '"Let agent author memories" for the model to write its own.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: memories.length,
              itemBuilder: (ctx, i) {
                final m = memories[i];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Icon(
                        _iconForKind(m.kind),
                        size: 18,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(m.content),
                    subtitle: Text(
                      '${m.kind} · used ${m.useCount}×',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Delete',
                      onPressed: () async {
                        await MemoryService.instance.delete(m.id);
                        ref.read(memoriesProvider.notifier).reload();
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  IconData _iconForKind(String kind) {
    switch (kind) {
      case 'preference':
        return Icons.tune;
      case 'fact':
        return Icons.fact_check_outlined;
      case 'goal':
        return Icons.flag_outlined;
      default:
        return Icons.notes_outlined;
    }
  }

  Future<void> _addMemory(BuildContext context) async {
    final controller = TextEditingController();
    var kind = 'preference';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('New memory'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'preference', label: Text('Preference')),
                  ButtonSegment(value: 'fact', label: Text('Fact')),
                  ButtonSegment(value: 'goal', label: Text('Goal')),
                  ButtonSegment(value: 'note', label: Text('Note')),
                ],
                selected: {kind},
                onSelectionChanged: (s) => setState(() => kind = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'One concise sentence about the user...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    await MemoryService.instance.create(kind: kind, content: text);
    ref.read(memoriesProvider.notifier).reload();
  }

  Future<void> _deleteAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all memories?'),
        content: const Text(
          'This removes every saved memory. The agent will lose long-term '
          'context the next time you chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await MemoryService.instance.deleteAll();
    ref.read(memoriesProvider.notifier).reload();
  }
}

class _ThemeModeSection extends ConsumerWidget {
  const _ThemeModeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text('System'),
              icon: Icon(Icons.settings_suggest_outlined),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text('Light'),
              icon: Icon(Icons.light_mode_outlined),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode_outlined),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) {
            Haptics.light();
            notifier.setMode(s.first);
          },
        ),
      ),
    );
  }
}
