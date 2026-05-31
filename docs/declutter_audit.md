# Declutter audit

Generated from the current local coverage run.

## Coverage baseline

Command:

```sh
flutter test --coverage --no-pub
dart tool/coverage_gate.dart --min-line=14.3
```

Current baseline:

- Tests: 107 passing
- Line coverage: 14.38% (1,327 / 9,228)
- Gate: 14.3% minimum, set just below the current baseline so future changes do not quietly reduce coverage

## Highest-value coverage targets

These files combine high uncovered line counts with user-facing or core behavior:

| File | Missed lines | Current coverage |
| --- | ---: | ---: |
| `lib/ui/settings/settings_screen.dart` | 1,142 | 0.95% |
| `lib/ui/chat/chat_screen.dart` | 1,057 | 0.09% |
| `lib/ui/chat/input_bar.dart` | 442 | 0.00% |
| `lib/core/agent/agent_session.dart` | 292 | 2.01% |
| `lib/ui/chat/message_bubble.dart` | 289 | 0.00% |
| `lib/core/storage/database.dart` | 283 | 51.04% |
| `lib/ui/settings/tools_permission_screen.dart` | 203 | 0.98% |
| `lib/ui/settings/hf_browser_screen.dart` | 184 | 0.00% |
| `lib/ui/settings/local_model_section.dart` | 176 | 1.12% |
| `lib/core/bootstrap/bootstrap_service.dart` | 172 | 2.27% |

## Clutter hotspots

### Oversized UI screens

The largest source files are screen-level widgets:

- `lib/ui/settings/settings_screen.dart`: 2,772 lines
- `lib/ui/chat/chat_screen.dart`: 2,287 lines
- `lib/ui/chat/input_bar.dart`: 1,027 lines
- `lib/ui/chat/message_bubble.dart`: 850 lines

Recommended cleanup: extract cohesive subwidgets and state helpers from these files before broad visual changes. Start with private widgets that already have clear boundaries, then add focused widget tests around the extracted behavior.

### Mixed persistence responsibilities

`lib/core/storage/database.dart` is 1,384 lines and currently mixes schema setup, migrations, import/export, FTS setup, chat persistence, and memory persistence.

Recommended cleanup: split by responsibility after adding tests for migrations and JSON import/export. Keep the public database API stable while moving implementation details into part files or smaller collaborators.

### Platform and tool surface area

The tool layer is broad:

- `lib/core/tools/cross_platform`: 15 Dart files
- `lib/core/tools/android`: 9 Dart files
- `lib/core/tools`: 9 Dart files

Recommended cleanup: prioritize tests around command construction, permission behavior, and failure modes. These are good coverage wins because they can usually be tested without rendering full app screens.

### Tracked build artifact

Resolved in this cleanup pass: `android/build/reports/problems/problems-report.html` was removed from version control. It was generated Android build output and `.gitignore` already excludes `/build/`.

The root-level `kolo_screenshot.png` file was also removed because it had no source references and appears to be a local screenshot artifact.

### Large local/generated files

The worktree contains generated local artifacts that are ignored but still add noise during inspection:

- `android/.gradle/`
- `coverage/`
- `.dart_tool/`
- `scripts/__pycache__/`

Recommended cleanup: leave them ignored, but delete local copies when preparing reviews or measuring repo size. Do not commit them.

`__pycache__/` and `/kolo_screenshot.png` are now explicitly ignored.

### Bootstrap archive in assets

`assets/bootstrap/bootstrap-aarch64.zip` is tracked and about 26 MB. It may be intentional because it is declared under Flutter assets.

Recommended cleanup: verify whether this binary artifact should live in Git or be fetched/released separately. If it stays in Git, document why and how it is produced.

## Suggested cleanup order

1. Add regression tests for `agent_session`, `bootstrap_service`, and tool command behavior.
2. Extract `settings_screen.dart` and `chat_screen.dart` into smaller widgets with tests around each extracted component.
3. Split `database.dart` internals after import/export and migration tests are in place.
4. Remove tracked generated artifacts, starting with `android/build/reports/problems/problems-report.html` if it is not intentional.
5. Decide whether `assets/bootstrap/bootstrap-aarch64.zip` belongs in Git or in a release/download pipeline.
