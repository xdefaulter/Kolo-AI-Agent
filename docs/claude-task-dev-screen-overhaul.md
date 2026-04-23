# Claude Task: Dev Screen Overhaul — 4 Issues

You're working on Kolo AI Agent, a Flutter app. Fix ALL of these issues in one go:

## Issue 1: Input bar text color invisible
File: `lib/ui/chat/input_bar.dart`
The TextField at ~line 352 has NO explicit `style` property for text color. In certain themes/surface colors, the typed text becomes invisible (blends into `fillColor`). 
Fix: Add explicit `style: TextStyle(color: cs.onSurface)` (or `cs.onSurfaceVariant` for hint) to the TextField. Also set `cursorColor: cs.primary`.

## Issue 2: Dev screen shares agent session with main chat
File: `lib/ui/dev/dev_screen.dart`
Currently the dev screen uses `agentSessionProvider` (the SAME provider as main chat). This means starting a conversation in Dev Mode pollutes the main chat and vice versa. Dev must have its own completely isolated agent session.
Fix: Create a separate `devAgentSessionProvider` in dev_screen.dart that is its own StateNotifier<AgentSessionState> with its own AgentSession, its own ConversationManager, and its own cancel token. It should NOT share state with the main chat. The session should still use the same API provider (from `providersProvider`) and the same tool registry (from `devToolRegistryProvider`). But messages, streaming state, and conversation history must be completely separate.

## Issue 3: Add "Create Project" option in Dev screen
Currently the file tree has a "New Project" button that sends a message to AI asking it to create a project. This is OK but needs to also be accessible via a proper dialog.
Fix: Add a "New Project" FAB or prominent button that shows a dialog with:
- Project name field (text input)
- Project type dropdown (Flutter, Python, Node.js, Blank)
- Creates the directory at `/sdcard/KoloProjects/{name}` and optionally scaffolds a basic project (just the directory + a README for blank, `flutter create` for Flutter, etc.)
- After creating, refreshes the file tree and navigates into the project.

## Issue 4: Merge terminal + chat into ONE unified interface
Currently the Dev screen has TWO separate areas: AI chat (top) and Terminal (bottom) with a draggable divider. This is confusing and doesn't match Claude Code's UX.
Fix: Replace the split layout with a SINGLE unified terminal-like view. Design:
- ONE scrollable output area that shows both AI messages AND terminal output interleaved
- ONE input bar at the bottom that serves as both the chat input and terminal
- If the user types a command starting with `$`, it runs as a terminal command (inline, shown with `$` prefix)
- Otherwise it's sent to the AI agent
- Terminal command output appears inline in the same scrollable view
- AI responses appear as monospace blocks (like terminal output) — not as chat bubbles
- Remove the draggable divider entirely
- Keep the file tree drawer on the left
- Keep the toolbar at the top (project dir, file tree toggle, etc.)
- The whole vibe should be "terminal IDE" not "chat app with a terminal bolted on"

## Important Notes

- The dev screen uses its own `_DevMessage` model (NOT `ChatMessageUI`). After the refactor, the unified model should track both AI messages and terminal lines.
- Keep using `InputBar` widget for the input at the bottom, but make sure Issue 1 is fixed (text color).
- The `_sendToAI` method currently appends workspace context to the message. Keep that behavior.
- After all changes, run `flutter analyze` and fix any errors.
- Do NOT touch `agent_session.dart` or `agent_loop.dart` — they work fine. Just create a second provider instance for the dev screen.