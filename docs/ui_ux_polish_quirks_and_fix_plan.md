# UI/UX Polish Audit: Native Kotlin App

Owner: Kolo AI (native Kotlin rebuild)  
Date: 2026-06-01  
Scope: `kolo-native` chat + settings + local model flows  
Status: Findings-only + implementation plan (no code changes yet)

This doc captures all observed UI/UX issues (57+) with file/line references and a concrete fix plan.

---

## Audit Method

- Source reviewed:
  - `kolo-native/feature/chat/src/main/java/com/kolo/agent/feature/chat/ui/ChatScreen.kt`
  - `kolo-native/feature/chat/src/main/java/com/kolo/agent/feature/chat/ChatViewModel.kt`
  - `kolo-native/feature/settings/src/main/java/com/kolo/agent/feature/settings/ui/SettingsScreen.kt`
  - `kolo-native/feature/settings/src/main/java/com/kolo/agent/feature/settings/ui/LocalModelScreen.kt`
  - `kolo-native/feature/settings/src/main/java/com/kolo/agent/feature/settings/SettingsViewModel.kt`
  - `kolo-native/feature/settings/LocalModelViewModel.kt`
  - `kolo-native/core/settings/src/main/java/com/kolo/agent/core/settings/AppSettings.kt`
  - `kolo-native/app/src/main/java/com/kolo/agent/MainActivity.kt`

- Severity:
  - **P0**: Blocks onboarding or core tasks.
  - **P1**: Frequent friction or wrong assumptions.
  - **P2**: Clarity/performance polish that directly affects confidence.
  - **P3**: Nice-to-have consistency/robustness items.

---

## Quirks List

### 1) Chat list drawer / chat discovery

1. **P0** No first-run onboarding path when no provider is configured, so chat starts with a neutral empty message and no guided setup action.  
   - File: `kolo-native/feature/chat/src/main/java/com/kolo/agent/feature/chat/ui/ChatScreen.kt:463-466`

2. **P1** Folder list has a fixed `heightIn(max = 116.dp)`, hiding all folders on long lists and making folder selection unreliable.  
   - File: `ChatScreen.kt:184-187`

3. **P1** Search field has no clear button; query clear is cumbersome and hidden.  
   - File: `ChatScreen.kt:174-182`

4. **P1** Folder delete affordance is a tiny icon-only control with high mis-tap risk.  
   - File: `ChatScreen.kt:203-207`

5. **P1** Deleting folders has no confirm/undo, causing unrecoverable data rehoming changes.  
   - File: `ChatScreen.kt:203-207` + `ChatViewModel.kt:204-213`

6. **P1** Chat row action menu is icon-only and small; no explicit "more actions" label for accessibility users.  
   - File: `ChatScreen.kt:255-260`

7. **P1** Per-row menu expansion state is ephemeral (`remember` inside each row), causing state resets if list updates.  
   - File: `ChatScreen.kt:229-301`

8. **P1** Move to "No folder" action is not confirmed and its effect is unclear in the UI.  
   - File: `ChatScreen.kt:269-276`

9. **P1** Drawer settings action lacks state context/badge indicating setup issues (e.g., no provider, local model missing).  
   - File: `ChatScreen.kt:307-314`

10. **P1** New folder creation has no inline validation for blank/duplicate names.  
    - File: `ChatScreen.kt:317-341`

11. **P1** New chat action is always active even while a message is streaming, risking context loss if tapped mid-generation.  
    - File: `ChatContent.kt` flow: `ChatScreen.kt:168-171`

12. **P1** Chat drawer has no "active folder count / chat count" indicators for quick location awareness.  
    - File: `ChatScreen.kt:197-216`

13. **P1** `onCreateFolder` has no max-length feedback or keyboard submit flow.  
    - File: `ChatScreen.kt:317-340`

### 2) Chat timeline and loading behavior

14. **P1** Auto-scroll can jump to odd positions during stream updates because it always scrolls to `messages.size`.  
    - File: `ChatScreen.kt:365-369`

15. **P1** Error banner is visually low priority and can be lost when long history grows.  
    - File: `ChatScreen.kt:412-415`

16. **P1** Tool approval banner is inline and disrupts timeline flow while generation is active.  
    - File: `ChatScreen.kt:417-425`

17. **P1** Streaming, tool calls, loading indicator, and token usage have no priority hierarchy, causing visual ambiguity on state transitions.  
    - File: `ChatScreen.kt:442-471`

18. **P1** Empty state does not provide direct action links to provider/model setup; users can stop at “How can I help you?”.  
    - File: `ChatScreen.kt:463-466`

19. **P1** Empty chat does not mention offline/local-provider constraints or selected-provider expectations.  
    - File: `ChatScreen.kt:464-465`

20. **P1** Message list has no date separators and long chats become difficult to scan.  
    - File: `ChatScreen.kt:428-466`

21. **P1** Error state for streaming failures doesn't remain sticky long enough for user action in some flows.  
    - File: `ChatScreen.kt:437-438`

22. **P1** Token usage bar appears with no context label explaining whether counts are for the last turn or cumulative.  
    - File: `ChatScreen.kt:468-471`

23. **P1** No keyboard shortcut to quickly dismiss transient banners without touching.  
    - File: `ChatScreen.kt:412-415`, `ChatScreen.kt:417-425`

### 3) Header and model/provider controls

24. **P1** No provider/model indicator when provider is missing, leaving users uncertain which backend is active.  
    - File: `ChatScreen.kt:478-481`

25. **P1** Model picker button is small icon-only in top bar and easy to miss; mobile one-handed operation is awkward.  
    - File: `ChatScreen.kt:525-530`

26. **P1** Dropdown list has no visible loading states; local provider model refresh path is confusing for users.  
    - File: `ChatScreen.kt:531-536`

27. **P2** For non-local providers, refresh action is only available through menu and has no progress indicator.  
    - File: `ChatScreen.kt:563-573`

28. **P2** Provider mismatch can occur when model picker displays placeholder but backend still has unresolved active model path.  
    - File: `ChatScreen.kt:531-537`, `ChatViewModel.kt:350-356`

29. **P2** Model picker does not expose quick model search/filter when list size grows.  
    - File: `ChatScreen.kt:545-560`

### 4) Tool approval and tool message UX

30. **P1** Tool approval banner has no clear danger legend; action labels alone are too subtle for safety decisions.  
    - File: `ChatScreen.kt:605-614`, `ChatScreen.kt:595-692`

31. **P1** Tool arguments truncate at fixed length and hide critical context.  
    - File: `ChatScreen.kt:644-654`

32. **P1** Action grouping is too dense on narrow screens and may overflow.  
    - File: `ChatScreen.kt:658-693`

33. **P1** No explicit persistence cue for “Always Allow / Block”, so user cannot verify state change happened.  
    - File: `ChatScreen.kt:662-692`

34. **P1** “Deny” and “Block” affordances are visually similar in row placement and require stronger distinction.  
    - File: `ChatScreen.kt:680-692`

35. **P2** Tool result rendering in message bubbles hides machine-readable output and loses quick context.  
    - File: `ChatScreen.kt:733-760`

### 5) Message content and attachments

36. **P1** Non-image attachments are text-only tokens and cannot be opened or previewed.  
    - File: `ChatScreen.kt:758-787`

37. **P1** Attachment previews are not constrained to a max width in all cases, causing bubble over-expansion with long filenames.  
    - File: `ChatScreen.kt:770-787`

38. **P1** Message copy is only discoverable by long-press; no copy icon button or toast action label.  
    - File: `ChatScreen.kt:727-730`

39. **P1** No undo path if user copies wrong text or wants quoted copy blocks.  
    - File: `ChatScreen.kt:727-818` (copy helper usage)

40. **P2** Tool-result and system messages share same visual style as normal assistant response, reducing readability.  
    - File: `ChatScreen.kt:733-759`

### 6) Input area and sending flow

41. **P1** Attachment picker accepts any MIME file and then silently allows many unsupported formats.  
    - File: `ChatScreen.kt:836-838`

42. **P1** User cannot tell at a glance if attachments are image-capable for model vision input or just file metadata.  
    - File: `ChatScreen.kt:762-776`

43. **P1** Attachment chips have tiny remove control and no accessible text alternatives.  
    - File: `ChatScreen.kt:748-787`

44. **P1** Only first 3 attachments are fully visible with no dedicated full attachments sheet.  
    - File: `ChatScreen.kt:748-754`

45. **P1** Send button disabled logic ignores attachments readiness/read errors (e.g., failed conversion).  
    - File: `ChatScreen.kt:384-394`, `ChatViewModel.kt:327-511`

46. **P1** In chat streaming state, users cannot edit pending text; no draft lock explanation.  
    - File: `ChatScreen.kt:384-395`

47. **P1** Prompt library icon has no "templates available" badge; discoverability is low.  
    - File: `ChatScreen.kt:401-406`, `ChatScreen.kt:840-861`

48. **P1** Prompt insertion always appends `\\n\\n` without preview or edit confirmation.  
    - File: `ChatScreen.kt:399-402`

49. **P1** No visual feedback for template insertion success/failure.  
    - File: `ChatScreen.kt:840-861`

50. **P2** Enter/IME send can be hidden due top/bottom insets interactions in some layouts.  
    - File: `ChatScreen.kt:384-394`

### 7) Chat header and token UI

51. **P2** Header model title can become stale when active model changes during request in-flight.  
    - File: `ChatViewModel.kt:520-529`

52. **P2** No dedicated "provider health" indicator (remote auth, local runtime unavailable, fetch errors).  
    - File: `ChatScreen.kt:478-590`, `ChatViewModel.kt:349-356`

53. **P1** Local runtime / CPU/GPU mode is not surfaced in header, requiring navigation to settings to verify.  
    - File: `ChatScreen.kt:490-496`, `SettingsViewModel.kt:304-307`

### 8) Settings home and section navigation

54. **P2** Settings home lacks a quick status snapshot (active provider, local model path, tool approvals).  
    - File: `SettingsScreen.kt:136-163`

55. **P1** No settings search/filter; large custom tools/skills lists become hard to locate.  
    - File: `SettingsScreen.kt:170-181` + section screens around custom tool/skills items

56. **P1** Section navigation has no transition state memory for deep links and no section breadcrumb.  
    - File: `SettingsScreen.kt:50-64`

57. **P1** Top bar title changes but doesn't provide contextual description for the active section.  
    - File: `SettingsScreen.kt:55-61`

### 9) Provider management (major UX)

58. **P0** Add provider flow is one-way and can create unusable providers due missing validation (malformed base URL/API key requirements).  
    - File: `SettingsScreen.kt:423-494`

59. **P1** Add-provider remote preset has no immediate validation summary (endpoint + auth expectations).  
    - File: `SettingsScreen.kt:423-446`

60. **P1** Remote provider add/edit still allows duplicate names without disambiguation.  
    - File: `SettingsScreen.kt:423-446`

61. **P1** `Show more than 8 models` in provider card is offloaded to chat picker, causing context split.  
    - File: `SettingsScreen.kt:364-390`

62. **P1** Model list within provider card lacks search/filter and quick set-active feedback.
    - File: `SettingsScreen.kt:364-390`

63. **P2** Save path action accepts local path without existence/accessibility checks before persisting.  
    - File: `SettingsScreen.kt:332-346`

64. **P1** CPU/GPU chips are binary, but copy claims layers; user cannot tune offload amount.  
    - File: `SettingsScreen.kt:281-293`

65. **P1** Local model mode has no visual warning when manual path conflicts with imported active model.  
    - File: `SettingsScreen.kt:301-311`

66. **P1** Delete provider action has no confirmation and no soft-delete undo.  
    - File: `SettingsScreen.kt:395-397`

67. **P1** Local provider card hardcodes example labels and does not expose active imported model name cleanly.  
    - File: `SettingsScreen.kt:263-267`

68. **P2** Provider detail model endpoint edit allows blank/invalid values with no inline error messaging.  
    - File: `ProviderDetailDialog` block lines `516-531`

69. **P2** Custom headers editor is free-text without validation against malformed header lines.  
    - File: `SettingsScreen.kt:554-530`

70. **P1** Parsed headers silently ignore malformed lines without feedback.  
    - File: `SettingsScreen.kt:554-565`

### 10) Settings tools/customization

71. **P2** Tools section lacks list search and categorization UX parity (all tools in one stream).  
    - File: `SettingsScreen.kt:567-599`

72. **P2** Custom tool add has no JSON schema lint/validation preview; malformed schema can break at runtime.  
    - File: `SettingsScreen.kt:652-699`

73. **P2** Skills section has no edit action and no ordering controls.  
    - File: `SettingsScreen.kt:746-784`

74. **P2** Memory section lacks timestamps, kind filters, and confirmation for destructive delete.  
    - File: `SettingsScreen.kt:826-851`

75. **P2** Instructions screen has no draft reset diff summary and no “discard changes” confirmation.  
    - File: `InstructionsSection` block lines `905-939`

76. **P2** Appearance screen has toggle “Show Token Usage” that appears disabled and nonfunctional.  
    - File: `SettingsScreen.kt:983-1000`

77. **P2** Phone control permissions are documented but not actionable in-app (no deep link/open settings button).  
    - File: `SettingsScreen.kt:945-976`

78. **P2** About screen hardcodes version and feature lists that drift from runtime; creates trust issues.  
    - File: `SettingsScreen.kt:1041-1049`

### 11) Local model management

79. **P1** Import path picker is file-first only and offers no manual paste/import-by-path fallback.  
    - File: `LocalModelScreen.kt:120-134`

80. **P1** Import process progress bar jumps from unknown to done with no ETA or step details.  
    - File: `LocalModelScreen.kt:260-320`

81. **P2** No model search/filter in imported model list for large local collections.  
    - File: `LocalModelScreen.kt:267-283`

82. **P2** Active model badge has no last-used indicator or model metadata beyond name/path.  
    - File: `LocalModelScreen.kt:260-268`

83. **P1** “No active model” warning does not provide direct path from Settings local models to import action.  
    - File: `LocalModelScreen.kt:320-325`

84. **P1** Deleting active model can leave active path unresolved without explicit post-delete recovery flow.  
    - File: `LocalModelScreen.kt:247-254` + `LocalModelViewModel.kt:79-83`

85. **P2** Delete confirmation modal is minimal and missing backup recommendation for local cache size.  
    - File: `LocalModelScreen.kt:14-38`

### 12) State and data integrity UX

86. **P1** Many state changes mutate only local UI state immediately and rely on background refresh, creating perceived non-responsiveness.  
    - File: `SettingsViewModel.kt:364-369`, `LocalModelViewModel.kt:51-55`

87. **P1** Some operations have no optimistic success feedback (save, delete, move, set active).  
    - File: `SettingsScreen.kt:394-397`, `ChatScreen.kt:88-90`

88. **P1** Chat send flow does not preserve in-progress send draft if an exception is thrown after DB write step.  
    - File: `ChatViewModel.kt:325-345`, `327-345`, `441-443`

89. **P1** Message attachments are persisted asynchronously with no progress/failed status.  
    - File: `ChatViewModel.kt:492-511`

90. **P1** Tool permission state updates can happen without immediate confirmation toast/snackbar.  
    - File: `SettingsViewModel.kt:158-166`

91. **P2** App settings include `Show Token Usage` placeholder that is not currently wired, creating broken expectations.  
    - File: `SettingsScreen.kt:999-1000`, `AppSettings.kt:33-39`

92. **P2** No regression-safe instrumentation for model-fetch failures (retry state is non-actionable to users).  
    - File: `SettingsViewModel.kt:329-356`, `SettingsScreen.kt:351-353`

93. **P2** No test coverage on critical UI state transitions (provider add/edit/delete, model import failure, local model selection).  
    - Repo wide: missing widget tests for `kolo-native` settings/chat state edges.

### 13) Navigation and back-stack behavior

94. **P1** No explicit draft-save warning when leaving chat with unsent content.  
    - File: `MainActivity.kt:42-68`, `ChatScreen.kt:360-363`

95. **P1** Deep-linking between settings/local models/chat loses in-progress unsaved work (no shared VM state handoff on route changes).  
    - File: `MainActivity.kt:69-110`

96. **P2** Back navigation from settings and local models always pops stack; there is no route guard when there is unsaved form data.  
    - File: `SettingsScreen.kt:50-68`, `MainActivity.kt:69-110`, local provider edit dialogs

97. **P2** No dedicated "go to chat" route from all settings sections causing multiple back presses in some flows.
    - File: `SettingsScreen.kt:170-181`, `MainActivity.kt:69-110`

---

## Fix Plan

### Phase 1: Foundations (P0/P1 stability pass)
Goal: unblock onboarding and prevent critical dead-end states.

1. Add first-run UX and onboarding banner in chat empty state
   - Files: `ChatScreen.kt`, `ChatViewModel.kt`
   - Add: setup CTA cards for provider + local model prerequisites.
   - Acceptance:
     - New users always see clear actions when provider/model missing.
     - No generation call can be started without actionable backend selection.

2. Add provider/model health indicators
   - Files: `ChatHeader` and `ChatScreen.kt`, `ChatViewModel.kt`
   - Add explicit active provider/model chips: active provider, model, backend type, local runtime status.
   - Acceptance:
     - Backend status visible at all times in one glance.
     - Local provider clearly indicates path/source and runtime availability.

3. Fix folder/chat drawer clipping and folder actions discoverability
   - Files: `ChatScreen.kt`
   - Remove fixed max height for folder section; add sectioned sticky header and search clear button.
   - Add confirmation dialog for folder delete; rename and duplicate prevention.
   - Acceptance:
     - All folders reachable on long lists.
     - Delete is intentional with confirm + undo.

4. Validate provider creation and show immediate provider edit state
   - Files: `SettingsScreen.kt`, `SettingsViewModel.kt`, `ProviderConfig*` model code if needed.
   - Add URL validation, required field hints, duplicate detection.
   - Acceptance:
     - Add provider cannot produce malformed base URL state.
     - Duplicate names are disambiguated by URL/alias.

### Phase 2: Chat UX and interaction reliability
Goal: lower friction for message composition, generation, and comprehension.

1. Improve input and attachment UX
   - Files: `ChatScreen.kt` (input bar + send flow), `ChatViewModel.kt` (persist attachments)
   - Add attachment type chips (image/file), attachment limits info, preview sheet, larger remove targets.
   - MIME filtering guidance and conversion status indicator.
   - Acceptance:
     - Users know exactly what can be sent.
     - Attachment send states persist until DB+storage confirmation.

2. Improve timeline readability and interruption handling
   - Files: `ChatScreen.kt`, `ChatViewModel.kt`
   - Add date separators, anchored banner region, clearer state ribbons: thinking vs streaming vs loading.
   - Improve cancelation and rollback messaging.
   - Acceptance:
     - Timeline remains scannable over long sessions.
     - State transitions are obvious with no hidden generation status.

3. Improve message UX
   - Files: `ChatScreen.kt`
   - Add message action buttons (copy, retry copy, open attachment), tool result cards, timestamp + date.
   - Better visual differentiation for tool messages and error messages.
   - Acceptance:
     - Users can act on tool outputs directly.
     - Tool messages are easier to parse.

### Phase 3: Settings quality pass
Goal: make providers, local models, and permissions manageable at scale.

1. Redesign provider card to support scale
   - Files: `SettingsScreen.kt`
   - Add pagination/search for model list and provider-level model management sheet.
   - Show path validation status for manual overrides.
   - Add delete confirmations and edit actions for all custom resources.
   - Acceptance:
     - Provider configuration scales to 50+ models without lost context.
     - Dangerous ops are reversible/confirmable.

2. Add settings search and section navigation quality
   - Files: `SettingsScreen.kt`
   - Add top-level search, section breadcrumb, and quick status chips.
   - Acceptance:
     - Any tool/custom/skill/memory item is retrievable quickly in one interaction.

3. Local model management improvements
   - Files: `LocalModelScreen.kt`, `LocalModelViewModel.kt`
   - Add model list search/filter and exists-check for manual paths.
   - Add post-delete recovery suggestions and clearer active model state transitions.
   - Acceptance:
     - Users can recover from model-delete scenarios without dead ends.
     - Invalid paths cannot be set accidentally.

### Phase 4: Navigation/state consistency
Goal: avoid uncommitted/hidden state and broken expectations.

1. Back-press and form-guard handling
   - Files: `MainActivity.kt`, `SettingsScreen.kt`, dialogs in provider/custom tools sections
   - Add route guards for unsaved provider edits/custom tool/skills instructions.
   - Add confirmation for discard.

2. Persistent UI state and feedback
   - Files: `ChatViewModel.kt`, `SettingsViewModel.kt`, `SettingsScreen.kt`
   - Add snackbars/toasts for saves, deletes, mode changes, fetch outcomes.
   - Ensure async failures surface actionable retry options.

3. Remove stale placeholder toggles
   - File: `SettingsScreen.kt`, `AppSettings.kt`
   - Remove non-functional settings flags or implement them end-to-end.

---

## Acceptance Checklist (End State)

- [ ] Users can start with zero setup and still clearly complete setup in under 3 taps.
- [ ] Every destructive action requires confirmation and provides undo/recover where feasible.
- [ ] Provider/model picker remains usable with large remote model lists.
- [ ] Attachment send/preview flow clearly communicates what is sendable and attachment persistence state.
- [ ] Tool permissions are understandable, with clear danger and persistence cues.
- [ ] All dialogs and edit flows validate input and expose inline errors.
- [ ] Settings and chat preserve user context across route changes.
- [ ] No non-functional switches/toggles remain in settings.

---

## Suggested Implementation Order

1. Fix core blockages: onboarding, provider/model selection safety, folder list clipping (`P0/P1`).
2. Chat message + input/attachment robustness (`P1`).
3. Provider and local model management scale (`P1`).
4. Settings quality polish and search (`P2`).
5. Accessibility and navigation hardening (`P2`).

---

## Risk / Dependencies

- No storage schema migration required for many UI fixes; validation and state guards are additive.
- Some improvements may require `Material3` test IDs and test tags.
- Local model/path validation may require file permissions checks and URI normalization utility.
- Tooling tests may be needed for `kolo-native` if existing CI coverage is minimal on UI state transitions.

---

## Notes

- This doc intentionally focuses on user-perceived UX first, then implementation.
- If you want, I can now convert this into a phased issue breakdown with estimated effort (XS/S/M/L) per item and generate an execution branch plan.
