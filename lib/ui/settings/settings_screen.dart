import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/provider.dart';
import '../../core/providers_state.dart';
import '../../core/tools/tool_bootstrap.dart';
import '../../core/tools/android/vlm_analyzer.dart';
import '../../core/agent/agent_settings.dart';
import '../../core/storage/database.dart';
import 'tools_permission_screen.dart';

// ---- Settings Screen ----

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(providersProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- API Providers ----
          Text('API Providers', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Manage your OpenAI-compatible API endpoints. Each can have multiple models.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 12),

          ...providers.map((p) => _ProviderCard(provider: p)),
          const SizedBox(height: 8),

          // Add provider buttons
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProviderScreen())),
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

          const SizedBox(height: 24),

          // ---- Tool Permissions ----
          Text('Tool Permissions', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Configure which tools require confirmation.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolsPermissionScreen())),
            icon: const Icon(Icons.build_outlined),
            label: Text('Manage ${bootstrapTools().all.length} Tools'),
          ),

          const SizedBox(height: 24),

          // ---- Vision Model ----
          Text('Vision Model', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Configure the model for screen analysis & phone control. Some models (GPT-4o, Gemini) support both text and vision.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          const _VisionModelSection(),

          const SizedBox(height: 24),

          // ---- Agent Settings ----
          Text('Agent', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Configure how the agent behaves during conversations.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          _MaxIterationsTile(),

          const SizedBox(height: 24),

          // ---- Data Management ----
          Text('Data', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Manage your chat history and app data.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Clear All Chats'),
                  subtitle: const Text('Delete all conversations permanently'),
                  onTap: () => _clearAllChats(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About'),
                  subtitle: Text('v0.1.0 · ${bootstrapTools().all.length} tools', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
                  onTap: () => _showAbout(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllChats(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Chats?'),
        content: const Text('This will permanently delete all conversations. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AppDatabase.instance.deleteAllChats();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All chats deleted'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Kolo AI Agent',
      applicationVersion: '0.1.0',
      applicationIcon: Icon(Icons.smart_toy, size: 48, color: Theme.of(context).colorScheme.primary),
      children: [
        Text('Unlimited AI assistant with ${bootstrapTools().all.length} tools.'),
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
            Text('Add from Preset', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...ProviderPresets.defaults.map((preset) => ListTile(
                  title: Text(preset.name),
                  subtitle: Text(preset.baseUrl, style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: () {
                    ref.read(providersProvider.notifier).addProvider(preset);
                    Navigator.pop(context);
                  },
                )),
          ],
        ),
      ),
    );
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
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProviderDetailScreen(provider: provider))),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(provider.isActive ? Icons.cloud_done : Icons.cloud_outlined,
                      color: provider.isActive ? Colors.green : cs.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(provider.name, style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.red.withValues(alpha: 0.7)),
                    onPressed: () {
                      ref.read(providersProvider.notifier).removeProvider(provider.id);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(provider.baseUrl, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
              const SizedBox(height: 4),
              if (activeModel != null)
                Text('Active: ${activeModel.label}', style: TextStyle(fontSize: 13, color: cs.primary, fontWeight: FontWeight.w600))
              else
                Text('No model selected', style: TextStyle(fontSize: 13, color: cs.error)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Chip(
                    label: Text('${provider.models.length} model${provider.models.length == 1 ? '' : 's'}'),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  if (provider.canFetchModels)
                    ActionChip(
                      label: const Text('Fetch'),
                      avatar: const Icon(Icons.refresh, size: 14),
                      onPressed: () async {
                        final count = await ref.read(providersProvider.notifier).fetchModels(provider.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(count > 0 ? 'Added $count new models' : 'No new models found')),
                          );
                        }
                      },
                    ),
                  const SizedBox(width: 8),
                  if (!provider.isActive)
                    ActionChip(
                      label: const Text('Set Active'),
                      onPressed: () => ref.read(providersProvider.notifier).setActiveProvider(provider.id),
                    ),
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
  ConsumerState<ProviderDetailScreen> createState() => _ProviderDetailScreenState();
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
    _modelsEndpointController = TextEditingController(text: _provider.modelsEndpoint ?? '');
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
          IconButton(icon: const Icon(Icons.save), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Connection Settings ----
          Text('Connection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder(), hintText: 'My API Provider')),
          const SizedBox(height: 12),
          TextFormField(controller: _urlController, decoration: const InputDecoration(labelText: 'Base URL', border: OutlineInputBorder(), hintText: 'https://api.openai.com/v1')),
          const SizedBox(height: 12),
          TextFormField(
            controller: _keyController,
            decoration: InputDecoration(
              labelText: 'API Key',
              border: const OutlineInputBorder(),
              hintText: 'sk-...',
              suffixIcon: IconButton(icon: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscureKey = !_obscureKey)),
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
                  final count = await ref.read(providersProvider.notifier).fetchModels(_provider.id);
                  if (context.mounted) {
                    _refreshProvider();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(count > 0 ? 'Added $count new models' : 'No new models found'),
                      behavior: SnackBarBehavior.floating,
                    ));
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
              Text('Models (${_provider.models.length})', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
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
                  Icon(Icons.model_training, size: 48, color: cs.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 8),
                  Text('No models yet', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
                  const SizedBox(height: 8),
                  if (_provider.canFetchModels)
                    FilledButton.tonal(onPressed: () async {
                      await ref.read(providersProvider.notifier).fetchModels(_provider.id);
                      _refreshProvider();
                    }, child: const Text('Fetch Models')),
                  if (!_provider.canFetchModels)
                    FilledButton.tonal(onPressed: () => _showAddModelDialog(context), child: const Text('Add Model Manually')),
                ],
              ),
            )
          else
            ..._provider.models.map((model) => _ModelTile(
                  model: model,
                  isActive: model.modelId == (_provider.activeModel?.modelId),
                  onSelect: () {
                    ref.read(providersProvider.notifier).setActiveModel(_provider.id, model.modelId);
                    _refreshProvider();
                  },
                  onDelete: () {
                    ref.read(providersProvider.notifier).removeModel(_provider.id, model.modelId);
                    _refreshProvider();
                  },
                )),
        ],
      ),
    );
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
      modelsEndpoint: _modelsEndpointController.text.trim().isEmpty ? null : _modelsEndpointController.text.trim(),
    );
    ref.read(providersProvider.notifier).updateProvider(updated);
    setState(() => _provider = updated);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Provider saved')));
  }

  void _showAddModelDialog(BuildContext context) {
    final modelIdController = TextEditingController();
    final displayNameController = TextEditingController();
    final maxTokensController = TextEditingController(text: '4096');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Model'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: modelIdController, decoration: const InputDecoration(labelText: 'Model ID *', hintText: 'gpt-4o, llama3.2, etc.')),
            const SizedBox(height: 12),
            TextField(controller: displayNameController, decoration: const InputDecoration(labelText: 'Display Name (optional)', hintText: 'GPT-4o')),
            const SizedBox(height: 12),
            TextField(controller: maxTokensController, decoration: const InputDecoration(labelText: 'Max Tokens', hintText: '4096'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (modelIdController.text.trim().isEmpty) return;
              final model = ModelConfig(
                modelId: modelIdController.text.trim(),
                displayName: displayNameController.text.trim().isEmpty ? null : displayNameController.text.trim(),
                maxTokens: int.tryParse(maxTokensController.text) ?? 4096,
                isCustom: true,
              );
              ref.read(providersProvider.notifier).addModel(_provider.id, model);
              _refreshProvider();
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final ModelConfig model;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  const _ModelTile({required this.model, required this.isActive, required this.onSelect, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: isActive ? cs.primary : cs.onSurface.withValues(alpha: 0.4)),
      title: Text(model.label, style: TextStyle(fontWeight: isActive ? FontWeight.w600 : FontWeight.normal)),
      subtitle: Text([
        model.modelId,
        if (model.contextWindow != null) '${(model.contextWindow! / 1000).round()}k ctx',
        '${model.maxTokens} tok',
        if (model.isCustom) 'custom',
      ].join(' · '), style: const TextStyle(fontSize: 11)),
      trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onDelete),
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
  final _urlController = TextEditingController(text: 'https://api.openai.com/v1');
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
          Text('Create a new OpenAI-compatible API connection.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 16),
          TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Name *', border: OutlineInputBorder(), hintText: 'My Provider')),
          const SizedBox(height: 12),
          TextFormField(controller: _urlController, decoration: const InputDecoration(labelText: 'Base URL *', border: OutlineInputBorder(), hintText: 'https://api.openai.com/v1')),
          const SizedBox(height: 12),
          TextFormField(controller: _keyController, decoration: const InputDecoration(labelText: 'API Key', border: OutlineInputBorder(), hintText: 'sk-...'), obscureText: true),
          const SizedBox(height: 12),
          TextFormField(
            controller: _modelsEndpointController,
            decoration: const InputDecoration(labelText: 'Models Endpoint (optional)', border: OutlineInputBorder(), hintText: 'https://api.openai.com/v1/models', helperText: 'Leave empty to use {baseUrl}/models'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              if (_nameController.text.trim().isEmpty || _urlController.text.trim().isEmpty) return;
              final provider = ProviderConfig(
                name: _nameController.text.trim(),
                baseUrl: _urlController.text.trim(),
                apiKey: _keyController.text.trim(),
                modelsEndpoint: _modelsEndpointController.text.trim().isEmpty ? null : _modelsEndpointController.text.trim(),
              );
              ref.read(providersProvider.notifier).addProvider(provider);
              Navigator.pop(context);
            },
            child: const Text('Create Provider'),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text('Or start from a preset:', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...ProviderPresets.defaults.map((preset) => ListTile(
                title: Text(preset.name),
                subtitle: Text(preset.baseUrl, style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.add),
                onTap: () {
                  ref.read(providersProvider.notifier).addProvider(preset);
                  Navigator.pop(context);
                },
              )),
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
                ref.read(visionModelConfigProvider.notifier).update(
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
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7)),
                    ),
                  ),
                ],
              ),
            ],

            if (visionConfig.mode == VisionModelMode.separate) ...[
              Text('Select Vision Provider & Model', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),

              // Provider dropdown
              DropdownButtonFormField<String>(
                value: visionConfig.providerId,
                decoration: const InputDecoration(
                  labelText: 'Vision Provider',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: providers.map((p) => DropdownMenuItem(
                  value: p.id,
                  child: Text(p.name),
                )).toList(),
                onChanged: (id) {
                  ref.read(visionModelConfigProvider.notifier).update(
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
                Builder(builder: (context) {
                  final provider = providers.where((p) => p.id == visionConfig.providerId).firstOrNull;
                  if (provider == null) return const SizedBox.shrink();
                  return DropdownButtonFormField<String>(
                    value: visionConfig.modelId != null && provider.models.any((m) => m.modelId == visionConfig.modelId)
                      ? visionConfig.modelId
                      : null,
                    decoration: const InputDecoration(
                      labelText: 'Vision Model',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: provider.models.map((m) => DropdownMenuItem(
                      value: m.modelId,
                      child: Text(m.label),
                    )).toList(),
                    onChanged: (id) {
                      ref.read(visionModelConfigProvider.notifier).update(
                        VisionModelConfig(
                          mode: VisionModelMode.separate,
                          providerId: visionConfig.providerId,
                          modelId: id,
                        ),
                      );
                    },
                  );
                }),

              const SizedBox(height: 8),
              Text(
                'Tip: Use a model with vision capabilities — GPT-4o, Gemini 2.5 Pro, Claude Sonnet, etc.',
                style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ],
        ),
      ),
    );
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
                Text('Max Iterations', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('$maxIter', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                )),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Maximum number of think-act-observe cycles per message. Higher = longer tasks, lower = faster but may not finish complex tasks.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
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
                AppDatabase.instance.saveSetting('max_iterations', v.toString());
              },
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('5 (quick)', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4))),
                Text('100 (deep)', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}