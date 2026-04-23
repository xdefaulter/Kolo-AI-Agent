# Claude Task: Improve Iterative Coding Feature in Kolo AI Agent

## What You're Working On

Kolo AI Agent is a Flutter app that runs an autonomous AI agent loop on Android/iOS. The agent reads files, writes files, runs shell commands, and calls tools in a think→act→observe loop. Your job is to make the agent dramatically better at **iterative coding** — editing code, searching codebases, and fixing errors in a loop.

## Current Architecture

Key files:
- `lib/core/agent/agent_loop.dart` — Main while-loop: streams API calls, parses tool_calls, executes them, feeds results back. Yields `AgentEvent` stream.
- `lib/core/agent/agent_session.dart` — Glue between ChatScreen ↔ AgentLoop ↔ ToolRouter. Riverpod StateNotifier.
- `lib/core/agent/tool_router.dart` — Routes tool calls to executors with permission. Parallel execution via `Future.wait`.
- `lib/core/agent/conversation_manager.dart` — Message history with token budget (~4 chars/token, 32K max).
- `lib/core/agent/system_prompt.dart` — System prompt builder with tool guidelines.
- `lib/core/agent/agent_settings.dart` — Max iterations config (1-100).
- `lib/core/tools/tool_base.dart` — Abstract `KoloTool`, `ToolResult`, `ToolPermission` enum (safe/sensitive/dangerous), `ToolPlatform` (all/android/ios).
- `lib/core/tools/tool_registry.dart` — `ToolRegistry` with register/get/getFunctionDefinitions.
- `lib/core/tools/tool_bootstrap.dart` — `bootstrapTools()` registers ~50 tools.
- `lib/core/tools/cross_platform/write_file.dart` — Simple overwrite or append.
- `lib/core/tools/cross_platform/read_file.dart` — Reads entire file.
- `lib/core/tools/cross_platform/new_tools.dart` — `GrepTool` (single-file), `ShellExecTool`, `ListFilesTool`, `DeleteFileTool`, etc.
- `lib/ui/chat/chat_screen.dart` — Chat UI, watches `agentSessionProvider` for streaming updates.

All tools extend `KoloTool` and must implement: `name`, `description`, `parameterSchema` (JSON Schema for OpenAI function calling), `permission`, `execute(params, context)` → `Future<ToolResult>`.

## Problems to Fix

### P0 — Must Have

**1. No diff/patch edit tool** — The agent overwrites entire files to change 3 lines. This wastes 10-50x tokens and is slow.  
→ Create `edit_file` tool: `path`, `old_string`, `new_string`, `replace_all` (bool). Find-and-replace with unified diff output. Fail if old_string not found or ambiguous (unless replace_all).

**2. read_file has no line range** — Returns entire 2000-line file, burning ~500K tokens to see one function.  
→ Enhance existing `ReadFileTool` with optional `offset` (1-indexed) and `limit` params. Return content WITH line numbers prepended. Include total line count in metadata.

**3. No project-wide search** — `GrepTool` only searches one file. Agent needs to find usages, class definitions across a project.  
→ Create `search_files` tool: `pattern` (regex), `path` (root dir), `file_glob` (e.g. `*.dart`), `output_mode` (files_only/content/count), `context` (context lines). Search across directory tree.

**4. System prompt lacks coding workflow** — Has phone control workflow but no coding guidance.  
→ Add "Coding Workflow" section to `system_prompt.dart`:
  - Always `read_file` (with line range) before editing
  - Use `edit_file` not `write_file` for changes (saves tokens)
  - Use `search_files` to navigate codebase
  - Run tests/analysis after changes (shell_exec)
  - Explain changes in natural language between tool calls

### P1 — Should Have

**5. shell_exec lacks persistent working directory** — Each call is independent, no `cd` persistence.  
→ Add optional `workingDirectory` persistence or `project_root` concept. Simplest: add a `set_project_root` tool that stores the root in a session singleton, then all tools default to relative paths under it.

**6. No structured build/test output** — Agent has to parse raw compiler output.  
→ Enhance `ShellExecTool` or add `run_flutter_task` tool that runs `flutter analyze`/`flutter test`/`flutter build` and returns structured errors array [{file, line, message, severity}].

**7. Tool result metadata** — Results are plain text, no structure.  
→ Add `metadata` fields to tool results: `category` (file_edit, build, search), `duration_ms`, `lines_changed`.

## Implementation Rules

1. New tools go in `lib/core/tools/cross_platform/` (or a new `lib/core/tools/coding/` subfolder if you prefer — just import and register them)
2. Register in `lib/core/tools/tool_bootstrap.dart`
3. Follow existing `KoloTool` pattern exactly
4. `parameterSchema` must be valid JSON Schema for OpenAI function calling
5. Permissions: `safe` for read-only, `sensitive` for writes, `dangerous` for shell
6. No new package dependencies — use `dart:io`, `dart:convert` only
7. `flutter analyze` must pass with zero errors
8. Do NOT change `agent_loop.dart`, `tool_router.dart`, or `agent_session.dart` — new tools work within the existing framework
9. Keep tool output concise but informative (it's sent back to the LLM as context)

## Files to Create/Edit

1. **CREATE** `lib/core/tools/cross_platform/edit_file.dart` — The `edit_file` tool (P0 #1)
2. **EDIT** `lib/core/tools/cross_platform/read_file.dart` — Add offset/limit/line numbers (P0 #2)
3. **CREATE** `lib/core/tools/cross_platform/search_files.dart` — The `search_files` tool (P0 #3)
4. **EDIT** `lib/core/agent/system_prompt.dart` — Add coding workflow section (P0 #4)
5. **EDIT** `lib/core/tools/tool_bootstrap.dart` — Register new tools
6. **CREATE** `lib/core/tools/cross_platform/project_tools.dart` — `set_project_root` tool (P1 #5)
7. **CREATE** (optional) `lib/core/tools/cross_platform/flutter_task.dart` — Structured flutter analyze/test (P1 #6)

After all changes, run `flutter analyze` and fix any issues.