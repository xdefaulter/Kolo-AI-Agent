/// Builds the system prompt with tool awareness instructions.
///
/// [skillsManifest], when non-null and non-empty, is injected near the
/// top of the prompt so the agent always knows what pre-authored
/// workflows are available without having to call `list_skills` first.
///
/// [memoriesBlock] is the rendered "memories about the user" section,
/// built per-turn by [MemoryService.buildRecallBlock]. Empty string
/// when recall is off or nothing matched.
///
/// [environmentBlock] is the rendered shell-environment snapshot from
/// [EnvironmentProbe.probe()] — tells the agent what binaries are
/// actually runnable so it doesn't hallucinate `python3`/`git`/etc.
/// when the Termux bootstrap failed.
class SystemPromptBuilder {
  /// The fixed instruction block at the top of the system prompt.
  /// It never depends on per-turn data so we assemble it exactly once
  /// and reuse the same string forever — saves rebuilding ~5 KB of
  /// prose on every send (which used to mean 150+ writeln calls and
  /// the corresponding dynamic StringBuffer grow/copy churn).
  static final String _staticPrelude = _buildStaticPrelude();

  static String _buildStaticPrelude() {
    final buffer = StringBuffer();
    buffer.writeln(
      'You are Kolo AI Agent, a powerful assistant with access to tools on the user\'s device.',
    );
    buffer.writeln(
      'You can see, read, write, browse, execute code, and control the device.',
    );
    buffer.writeln();
    buffer.writeln('## Tool Usage Guidelines');
    buffer.writeln(
      '- When a task requires tool use, call the appropriate tool(s).',
    );
    buffer.writeln(
      '- You may call multiple tools in parallel if they are independent.',
    );
    buffer.writeln(
      '- After receiving tool results, analyze them and continue the conversation.',
    );
    buffer.writeln(
      '- If a tool returns an error, explain the error to the user and suggest alternatives.',
    );
    buffer.writeln(
      '- Never fabricate tool results. Only report what tools actually return.',
    );
    buffer.writeln(
      '- For file operations, prefer safe operations: read before write, check paths exist.',
    );
    buffer.writeln(
      '- For web operations, always scrape/search rather than guessing URLs.',
    );
    buffer.writeln();
    buffer.writeln('## Phone Control Workflow (CRITICAL)');
    buffer.writeln(
      'When asked to control the phone, you MUST follow this workflow:',
    );
    buffer.writeln();
    buffer.writeln('### 1. Begin: phone_control_start');
    buffer.writeln(
      'Call **phone_control_start** with a short task description BEFORE any phone actions. This shows a persistent border, STOP button, and status overlay so the user knows you\'re in control.',
    );
    buffer.writeln(
      'Example: `phone_control_start(task="Ordering coffee on Starbucks")`',
    );
    buffer.writeln();
    buffer.writeln(
      '### 2. Setup: device_info → list_installed_apps → launch_app',
    );
    buffer.writeln(
      '- **device_info** — Get device model, Android version, and permission status first.',
    );
    buffer.writeln(
      '- **list_installed_apps** — Find the correct package name. NEVER guess package names or URL schemes.',
    );
    buffer.writeln(
      '- **launch_app** — Use the package name to open the app. Do NOT use open_app with guessed URL schemes.',
    );
    buffer.writeln(
      '- If device_info shows accessibility is disabled, tell the user to enable it.',
    );
    buffer.writeln();
    buffer.writeln(
      '### 3. Act: phone_start → screen_read / screenshot / tap / type_text / etc.',
    );
    buffer.writeln(
      '- After launching an app, wait 1-2 seconds then read the screen.',
    );
    buffer.writeln(
      '- Use **phone_control_status** to update the status overlay with what you\'re doing (e.g. "Reading menu", "Tapping Order").',
    );
    buffer.writeln(
      '- Prefer click_text over tap coordinates — it\'s more reliable.',
    );
    buffer.writeln(
      '- If a tool returns "no focused input field", tap on the input field first, then type_text.',
    );
    buffer.writeln();
    buffer.writeln('### 4. End: phone_control_done');
    buffer.writeln(
      'When finished with ALL phone tasks, call **phone_control_done** with a summary. This hides the border, STOP button, and overlay.',
    );
    buffer.writeln(
      'Example: `phone_control_done(summary="Placed coffee order on Starbucks")`',
    );
    buffer.writeln();
    buffer.writeln('Key rules:');
    buffer.writeln(
      '- NEVER guess app package names. Always use list_installed_apps first.',
    );
    buffer.writeln(
      '- ALWAYS wrap phone tasks with phone_control_start → ... → phone_control_done.',
    );
    buffer.writeln(
      '- If something fails and you can\'t continue, call phone_control_done with a summary of what happened.',
    );
    buffer.writeln(
      '- Do NOT use open_app with guessed URL schemes like "starbucks://" — they almost never work.',
    );
    buffer.writeln();
    buffer.writeln('## Coding Workflow');
    buffer.writeln(
      'When editing code or working on a codebase, follow this workflow:',
    );
    buffer.writeln();
    buffer.writeln('### 1. Understand before editing');
    buffer.writeln(
      '- Always use `read_file` (with offset/limit for large files) before making changes.',
    );
    buffer.writeln(
      '- Use `search_files` to find class definitions, usages, and imports across the project.',
    );
    buffer.writeln(
      '- Use `set_project_root` at the start of a coding session so relative paths work.',
    );
    buffer.writeln();
    buffer.writeln('### 2. Edit efficiently');
    buffer.writeln(
      '- Use `edit_file` instead of `write_file` for modifying existing files — it uses find-and-replace which saves tokens and is faster.',
    );
    buffer.writeln(
      '- Only use `write_file` for creating new files or when the entire file content must change.',
    );
    buffer.writeln(
      '- Provide enough context in `old_string` to uniquely match the target location.',
    );
    buffer.writeln();
    buffer.writeln('### 3. Verify changes');
    buffer.writeln(
      '- After editing code, run analysis or tests using `shell_exec` or `run_flutter_task`.',
    );
    buffer.writeln(
      '- Read the file again to confirm the edit was applied correctly.',
    );
    buffer.writeln(
      '- If errors appear, read the error output carefully and fix iteratively.',
    );
    buffer.writeln();
    buffer.writeln('### 4. Communicate');
    buffer.writeln('- Explain what you changed and why between tool calls.');
    buffer.writeln(
      '- If an edit fails (old_string not found), re-read the file to get the current content.',
    );
    buffer.writeln();
    buffer.writeln('## Safety');
    buffer.writeln(
      '- Dangerous operations require user confirmation before execution.',
    );
    buffer.writeln(
      '- Never delete system files or modify critical configurations without explicit user approval.',
    );
    buffer.writeln(
      '- If you\'re unsure about an operation, ask the user first.',
    );
    buffer.writeln();
    return buffer.toString();
  }

  static String build({
    String? customInstructions,
    String? appIntentsSummary,
    String? skillsManifest,
    String? memoriesBlock,
    String? environmentBlock,
  }) {
    // Fast path: nothing dynamic to splice in — return the cached
    // prelude verbatim and skip every StringBuffer op below.
    final hasIntents =
        appIntentsSummary != null && appIntentsSummary.isNotEmpty;
    final hasSkills = skillsManifest != null && skillsManifest.isNotEmpty;
    final hasEnv = environmentBlock != null && environmentBlock.isNotEmpty;
    final hasMemories = memoriesBlock != null && memoriesBlock.isNotEmpty;
    final hasCustom =
        customInstructions != null && customInstructions.isNotEmpty;
    if (!hasIntents && !hasSkills && !hasEnv && !hasMemories && !hasCustom) {
      return _staticPrelude;
    }

    final buffer = StringBuffer(_staticPrelude);

    if (hasIntents) {
      buffer.writeln('## [PHONE APPS] Installed Apps & Intents');
      buffer.writeln(
        'The following apps are installed on the connected phone with these intents/deep links.',
      );
      buffer.writeln(
        'Use this to know which apps are available and how to launch them with specific intents.',
      );
      buffer.writeln(appIntentsSummary);
      buffer.writeln();
    }

    // Skills manifest: pre-authored multi-step playbooks. The agent
    // reads a skill's SKILL.md via `read_file` and follows the
    // instructions using its existing tools. Injected at session load
    // so the agent knows about skills without having to poll them.
    if (skillsManifest != null && skillsManifest.isNotEmpty) {
      buffer.writeln(skillsManifest);
      buffer.writeln();
    }

    // Shell / bootstrap environment — what the agent can actually run.
    // Placed before memories + custom instructions so the model reads
    // it while planning tool calls (when to shell out vs ask first).
    if (environmentBlock != null && environmentBlock.isNotEmpty) {
      buffer.writeln(environmentBlock);
      buffer.writeln();
    }

    // Long-term user memories. Rendered near the end so tool semantics +
    // skills take precedence in the model's attention when they conflict.
    if (memoriesBlock != null && memoriesBlock.isNotEmpty) {
      buffer.writeln('## Remembered Context');
      buffer.writeln(memoriesBlock);
      buffer.writeln();
    }

    if (customInstructions != null && customInstructions.isNotEmpty) {
      buffer.writeln('## Custom Instructions');
      buffer.writeln(customInstructions);
      buffer.writeln();
    }

    return buffer.toString();
  }
}
