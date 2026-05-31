# Claude Prompt: Improve Iterative Coding Feature in Kolo AI Agent

## Context

You are improving the **iterative coding capability** of Kolo AI Agent, a Flutter app that runs an autonomous AI agent loop (think→act→observe) on Android/iOS. The agent can read files, write files, execute shell commands, and call other tools in a loop until the task is done.

The current agent loop works like this:
1. User sends a message
2. AgentLoop streams the request to an OpenAI-compatible API
3. If the model returns tool_calls, the loop executes them (in parallel when possible)
4. Tool results are fed back as messages
5. The loop repeats up to `maxIterations` (default 20, max 100)
6. Streaming content, thinking chunks, and tool results are yielded as events in real-time

## Current Architecture (key files)

- `lib/core/agent/agent_loop.dart` — The main while-loop that streams API calls, parses tool calls, executes them, and feeds results back
- `lib/core/agent/agent_session.dart` — Glue between ChatScreen ↔ AgentLoop ↔ ToolRouter. Manages conversation history, streaming state via Riverpod StateNotifier
- `lib/core/agent/tool_router.dart` — Routes tool calls to executors with permission checks. Executes parallel calls via `Future.wait`
- `lib/core/agent/conversation_manager.dart` — Manages message history with token budget (~4 chars/token estimate, 32K token max)
- `lib/core/agent/system_prompt.dart` — Builds the system prompt with tool usage guidelines
- `lib/core/agent/agent_settings.dart` — Max iterations config (1-100)
- `lib/core/tools/tool_base.dart` — Abstract `KoloTool` class, `ToolResult`, `ToolPermission` enum
- `lib/core/tools/cross_platform/write_file.dart` — Simple write (overwrite or append)
- `lib/core/tools/cross_platform/read_file.dart` — Simple read entire file
- `lib/core/tools/cross_platform/new_tools.dart` — grep, shell_exec, file_stat, copy/move/delete, etc.
- `lib/ui/chat/chat_screen.dart` — Chat UI that watches agent session state for real-time streaming

## Problems with Iterative Coding Today

1. **No diff/patch tool** — The agent overwrites entire files every time. For a 500-line Dart file where it needs to change 3 lines, it re-sends all 500 lines in the write_file tool call AND consumes 500+ output tokens. This is extremely wasteful and slow.

2. **No file watching / hot reload** — When the agent writes code, it has no way to know if the code compiled, if there are errors, or if it needs to fix something. It can only manually call `shell_exec` to run `flutter build` or `dart analyze`.

3. **No search/grep across project** — The current `grep` tool searches a single file. The agent needs to search across an entire project (find usages, find class definitions, etc.) to navigate codebases effectively.

4. **Token waste on large files** — `read_file` returns the entire file. For a 2000-line file, that's ~500K tokens of context burned just to see one function. The agent needs line-range reading.

5. **No workspace/project awareness** — The agent has no concept of a "project directory." Every file path must be absolute. There's no workspace root, no `.gitignore` awareness, no understanding of project structure.

6. **System prompt lacks coding-specific guidance** — The system prompt has phone control workflow but no coding workflow (read→edit→test→fix loop).

7. **No edit confirmation / diff preview** — When the agent writes a file, there's no way to show the user a diff of what changed. No undo mechanism either.

8. **Tool results are plain text** — The agent returns raw `ToolResult.output` strings. Tool results have no structure (no line numbers, no error categories, no file paths extracted).

9. **No persistent tool state** — Each tool execution is independent. The agent can't track "which files I've modified this session" or "what errors have I seen."

10. **Parallel tool execution has no dependency awareness** — `executeToolsParallel` runs all tool calls simultaneously. If the model asks to "read file A then write to file A," parallel execution would race.

## Requested Improvements

### P0 — Must Have

**1. `edit_file` tool (diff/patch-based file editing)**
- Accept: `path`, `old_string`, `new_string`, `replace_all` (boolean)
- Find the exact `old_string` in the file, replace with `new_string`
- Return a unified diff of the change
- Fail if `old_string` not found (or found multiple times unless `replace_all=true`)
- This is the #1 improvement. It reduces token usage by 10-50x for edits.

**2. `read_file` enhancement — line range support**
- Add optional `offset` (1-indexed line number) and `limit` (max lines) params
- Return content with line numbers prepended
- Return total line count in metadata

**3. `search_files` tool — project-wide search**
- Accept: `pattern` (regex), `path` (root directory), `file_glob` (e.g., `*.dart`), `output_mode` (files_only/content/count)
- Search across multiple files in a directory tree
- Return matching files + line numbers + context lines

**4. Workspace/project awareness in system prompt**
- Add a "Coding Workflow" section to system_prompt.dart that instructs the model to:
  - Use `edit_file` instead of `write_file` for edits (saves tokens)
  - Always read before editing
  - Run tests/analysis after making changes
  - Use `search_files` to navigate the codebase
  - Track modifications per session

### P1 — Should Have

**5. `shell_exec` enhancement — working directory persistence**
- Accept a `session_id` param so multiple commands share the same working directory
- Or add a `cd`-like concept to the tool

**6. Build/test integration — `run_task` tool**
- A higher-level tool that runs common project tasks: `flutter analyze`, `flutter test`, `flutter build apk --debug`
- Parses the output and returns structured results (errors as array of {file, line, message})
- This avoids the model having to parse raw compiler output

**7. Tool result metadata enhancement**
- Add structured fields to ToolResult: `category` (file_edit, build, search, etc.), `duration_ms`, `tokens_saved` (for edit vs write comparison)
- The chat UI can then render tool results differently based on category

### P2 — Nice to Have

**8. File modification tracking**
- Track which files were modified in the current session
- Add a `list_modified_files` tool
- Show modification count in the UI

**9. Undo/revert for file edits**
- Before `edit_file` applies a change, save original content in memory (session-scoped)
- Add an `undo_edit` tool that reverts the last change to a file

**10. Dry-run mode for edits**
- `edit_file` with `dry_run=true` returns the diff without applying it
- Lets the user preview changes before committing

## What to Implement

Focus on P0 items first, then P1. For each:

1. Create/edit the tool Dart file(s) in `lib/core/tools/cross_platform/`
2. Register the new tools in `lib/core/tools/tool_registry.dart` (or `tool_bootstrap.dart`)
3. Update `system_prompt.dart` with coding workflow guidance
4. Ensure the tool's `parameterSchema` is valid JSON Schema for OpenAI function calling
5. Follow the existing `KoloTool` pattern exactly (name, description, parameterSchema, permission, execute)
6. Keep permission levels appropriate: `safe` for read-only, `sensitive` for writes, `dangerous` for shell

## Constraints

- All tools must extend `KoloTool` from `tool_base.dart`
- No new dependencies — use only `dart:io`, `dart:convert`, etc. (the `crypto` package is already available)
- Must work on Android (primary) — iOS is secondary
- Tool output is sent back to the LLM as plain text in the conversation, so keep it concise but informative
- The agent loop itself (`agent_loop.dart`, `tool_router.dart`) should NOT need changes for new tools
- Build must pass: `flutter analyze` should show zero errors

<!-- SUPPLY_CHAIN_SECURITY_POLICY_V1 -->

## Supply Chain Security Policy

Treat dependency installation, package execution, and build tooling as high-risk operations.

- Prefer pinned lockfile workflows: `npm ci`, `pnpm install --frozen-lockfile`, `yarn install --immutable`, or `bun install --frozen-lockfile`.
- Do not run `npm install`, `npx`, `pnpm dlx`, `yarn dlx`, `bunx`, `curl | sh`, `wget | sh`, or remote install scripts without explicit user approval.
- Do not install global packages unless the user explicitly approves the exact package name, version, and purpose.
- Use `sfw` explicitly when package-manager execution is required and available: `sfw npm ...`, `sfw npx ...`, `sfw pnpm ...`, `sfw yarn ...`, or `sfw bun ...`.
- Do not rely on shell aliases for safety; non-interactive agent shells may not load `~/.zshrc` or `~/.bashrc`.
- Assume lifecycle scripts are dangerous. Use `--ignore-scripts` by default unless the project clearly requires scripts, and stop to explain any required lifecycle script before allowing it.
- Do not add or upgrade dependencies casually. Prefer existing project dependencies and explain why any new package is necessary.
- Check package names for typosquatting, impersonation, abandoned packages, suspicious maintainers, and unexpected scope changes.
- Pin exact versions for new direct dependencies unless the repository has a different established policy.
- Never remove lockfiles or regenerate them unnecessarily. After dependency changes, summarize exactly what changed in `package.json` and lockfiles.
- Never commit secrets, tokens, `.env` files, npm auth tokens, SSH keys, or registry credentials.
- If a command would fetch or execute third-party code, state that clearly before running it.

