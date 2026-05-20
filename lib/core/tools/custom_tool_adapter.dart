import 'custom_tool_def.dart';
import 'tool_base.dart';

/// Runtime wrapper that presents a [CustomToolDef] to the agent as a
/// regular [KoloTool]. Dispatches by [CustomToolDef.kind] to the right
/// concrete implementation.
///
/// Shell custom tools are retained only as a legacy persisted kind; they
/// are no longer executed or registered by the chat tool bootstrap.
class CustomToolAdapter extends KoloTool {
  final CustomToolDef def;
  CustomToolAdapter(this.def);

  @override
  String get name => def.name;

  @override
  String get description => def.description;

  @override
  Map<String, dynamic> get parameterSchema => def.parameterSchema;

  @override
  ToolPermission get permission => def.permission;

  @override
  ToolPlatform get platform {
    return ToolPlatform.all;
  }

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    try {
      switch (def.kind) {
        case CustomToolKind.shell:
          return ToolResult.err(
            'Shell custom tools are disabled in this chat build.',
          );
        case CustomToolKind.prompt:
          return await _executePrompt(params, context);
        case CustomToolKind.composed:
          return await _executeComposed(params, context);
      }
    } on TemplateRenderError catch (e) {
      return ToolResult.err('Template render failed: ${e.message}');
    } catch (e) {
      return ToolResult.err('Custom tool "${def.name}" failed: $e');
    }
  }

  /// Fire a one-shot sub-LLM call with the configured system prompt +
  /// a rendered user message template. The response text becomes the
  /// tool's output. This works on any platform (no shell needed).
  ///
  /// Note: we use [renderPlainTemplate] (not shell-quoted) here because
  /// the rendered text is going to another LLM, not a shell. The safe
  /// character set is wider but still excludes template delimiters so
  /// `{{}}` in user input can't introduce a new placeholder.
  Future<ToolResult> _executePrompt(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final impl = def.implementation;
    final systemPrompt = impl['systemPrompt'] as String?;
    final userTemplate = impl['userTemplate'] as String?;
    if (systemPrompt == null || systemPrompt.isEmpty) {
      return ToolResult.err('Tool missing "systemPrompt" in implementation.');
    }
    if (userTemplate == null || userTemplate.isEmpty) {
      return ToolResult.err('Tool missing "userTemplate" in implementation.');
    }
    final call = context.subLlmCall;
    if (call == null) {
      return ToolResult.err(
        'Prompt-kind custom tools need an active LLM provider — configure '
        'one in Settings first.',
      );
    }
    final rendered = renderPlainTemplate(userTemplate, params);
    final response = await call(
      systemPrompt: systemPrompt,
      userMessage: rendered,
    );
    return ToolResult.ok(
      response,
      metadata: {'customToolId': def.id, 'kind': 'prompt'},
    );
  }

  /// Run a sequence of existing tools with template-substituted args.
  /// Each step's args are a Map<String, dynamic>; string values are
  /// scanned for `{{…}}` placeholders and substituted from an evolving
  /// context (starts with the invocation params, gains a `_previous`
  /// entry after each successful step so steps can chain).
  ///
  /// Permissions for each sub-step are enforced by the router — composed
  /// tools CANNOT bypass the user's approval flow for dangerous steps.
  Future<ToolResult> _executeComposed(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final steps = def.implementation['steps'];
    if (steps is! List || steps.isEmpty) {
      return ToolResult.err('Tool has no "steps" in implementation.');
    }
    final run = context.runToolByName;
    if (run == null) {
      return ToolResult.err(
        'Composed-kind custom tools must be invoked via the agent loop.',
      );
    }

    // Evolving template context: invocation params, then we add
    // `_previous` after each step so later steps can reference the last
    // output. Keep it simple — anything more complex belongs in a real
    // workflow engine.
    final tplCtx = <String, dynamic>{...params};
    final outputs = <String>[];

    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      if (step is! Map) {
        return ToolResult.err('Step $i is malformed.');
      }
      final toolName = step['tool'] as String?;
      final rawArgs = step['args'];
      if (toolName == null || toolName.isEmpty || rawArgs is! Map) {
        return ToolResult.err('Step $i must be {"tool":"<name>","args":{…}}.');
      }
      // Shallow-render each string value. Non-string values pass through
      // verbatim (no auto-stringification — tools expect typed args).
      final resolvedArgs = <String, dynamic>{};
      for (final e in rawArgs.entries) {
        final v = e.value;
        resolvedArgs[e.key as String] = v is String
            ? renderPlainTemplate(v, tplCtx)
            : v;
      }
      final res = await run(toolName, resolvedArgs);
      if (!res.success) {
        return ToolResult.err('Step $i ($toolName) failed: ${res.error}');
      }
      outputs.add('[step $i $toolName]\n${res.output}');
      tplCtx['_previous'] = res.output;
    }

    return ToolResult.ok(
      outputs.join('\n\n'),
      metadata: {
        'customToolId': def.id,
        'kind': 'composed',
        'stepCount': steps.length,
      },
    );
  }
}
