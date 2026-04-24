import 'dart:async';
import 'dart:io';

import 'custom_tool_def.dart';
import 'tool_base.dart';
import '../bootstrap/bootstrap_service.dart';

/// Runtime wrapper that presents a [CustomToolDef] to the agent as a
/// regular [KoloTool]. Dispatches by [CustomToolDef.kind] to the right
/// concrete implementation.
///
/// Currently only `shell` kind is supported. `prompt` and `composed`
/// throw a friendly error when executed, so they can be saved and
/// surfaced in Settings while the runtime catches up.
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
    // shell tools can only run on Android (we have a bootstrapped shell).
    // prompt/composed run anywhere.
    // shell kind is Android-only (needs /system/bin/sh); other kinds run
    // everywhere. `ToolPlatform.all` is the enum's cross-platform value.
    return def.kind == CustomToolKind.shell
        ? ToolPlatform.android
        : ToolPlatform.all;
  }

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    try {
      switch (def.kind) {
        case CustomToolKind.shell:
          return await _executeShell(params);
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
        return ToolResult.err('Step $i (${toolName}) failed: ${res.error}');
      }
      outputs.add('[step $i ${toolName}]\n${res.output}');
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

  Future<ToolResult> _executeShell(Map<String, dynamic> params) async {
    if (!Platform.isAndroid) {
      return ToolResult.err(
        'Shell-kind custom tools only run on Android (needs the Termux bootstrap).',
      );
    }
    final impl = def.implementation;
    final template = impl['command'] as String?;
    if (template == null || template.isEmpty) {
      return ToolResult.err('Tool definition missing "command" template.');
    }
    final timeoutSec = (impl['timeoutSec'] as num?)?.toInt() ?? 60;

    final rendered = renderTemplate(template, params);

    // Inject the Termux bootstrap env (PATH etc.) when available so the
    // command can resolve python3, node, etc. the same way ShellExecTool
    // does. Custom tools share that sandbox.
    Map<String, String>? env;
    final bootstrap = BootstrapService.instance;
    if (bootstrap.isReady) {
      // fullEnvironment is cached — avoids copying ~200 Platform.environment
      // entries on every tool invocation.
      env = bootstrap.fullEnvironment;
    }

    try {
      final result = await Process.run('/system/bin/sh', [
        '-c',
        rendered,
      ], environment: env).timeout(Duration(seconds: timeoutSec));
      final buf = StringBuffer();
      if (result.stdout.toString().isNotEmpty) buf.writeln(result.stdout);
      if (result.stderr.toString().isNotEmpty) {
        buf.writeln('STDERR: ${result.stderr}');
      }
      final output = buf.toString().trim();
      return ToolResult.ok(
        output.isEmpty ? '(no output, exit ${result.exitCode})' : output,
        metadata: {
          'exitCode': result.exitCode,
          'customToolId': def.id,
          'renderedCommand': rendered,
        },
      );
    } on TimeoutException {
      return ToolResult.err(
        'Custom tool "${def.name}" timed out after ${timeoutSec}s',
      );
    }
  }
}
