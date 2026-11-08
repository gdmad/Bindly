#!/bin/bash
# Compiles the pure-logic sources together with the test runner and executes them.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/LogicTests"
swiftc -O \
    BindAll/Store/ActionKey.swift \
    BindAll/Store/PushToTalkKey.swift \
    BindAll/Store/Settings.swift \
    BindAll/Store/LanguageToolURL.swift \
    BindAll/Actions/MaskAISlopRule.swift \
    BindAll/Actions/MaskAISlop.swift \
    BindAll/Actions/KeyboardLayoutMap.swift \
    BindAll/Actions/TextTool.swift \
    BindAll/Store/AppPaths.swift \
    BindAll/Store/HistoryStore.swift \
    BindAll/Store/HistoryMenuTitle.swift \
    BindAll/Store/UsageLog.swift \
    BindAll/Engines/AIEngine.swift \
    BindAll/Proofread/TextIssue.swift \
    BindAll/Proofread/WordBoundary.swift \
    BindAll/Proofread/UnderlineGeometry.swift \
    BindAll/Proofread/IssueMerger.swift \
    BindAll/Proofread/ProofreadCache.swift \
    BindAll/Proofread/ProofreadLanguage.swift \
    BindAll/Proofread/RecheckPolicy.swift \
    BindAll/Proofread/ProofreadClickPolicy.swift \
    BindAll/Proofread/HiddenBreaks.swift \
    BindAll/Proofread/ProofreadSkips.swift \
    BindAll/Proofread/FixAll.swift \
    BindAll/Proofread/PersonalDictionary.swift \
    BindAll/Proofread/PreSendPolicy.swift \
    BindAll/Voice/HoldKeyPolicy.swift \
    BindAll/App/StatusIconTwinkle.swift \
    BindAll/Store/ShortcutConflicts.swift \
    BindAll/Store/SelectionCommand.swift \
    BindAll/Proofread/TextOccurrence.swift \
    BindAll/UI/PanelPlacement.swift \
    BindAll/UI/PanelWidth.swift \
    BindAll/UI/ResultMarkdown.swift \
    BindAll/Voice/AudioLevelMeter.swift \
    BindAll/Proofread/ListMarkers.swift \
    BindAll/Proofread/AppOffsetMap.swift \
    BindAll/Engines/TranslationLayout.swift \
    BindAll/Engines/LanguagePair.swift \
    BindAll/Store/AppLanguages.swift \
    BindAll/Engines/OCRParagraphs.swift \
    BindAll/Engines/DocumentLayout.swift \
    BindAll/UI/PopupTilePacker.swift \
    BindAll/Engines/LanguageToolEngine.swift \
    BindAll/LocalServer/LocalServerLayout.swift \
    BindAll/LocalServer/LocalServerPort.swift \
    BindAll/LocalServer/LocalServerRelease.swift \
    BindAll/LocalServer/LocalServerManifest.swift \
    BindAll/Autocomplete/AutocompleteEngine.swift \
    BindAll/Autocomplete/AutocompleteLearningStore.swift \
    BindAll/Autocomplete/LearnedWordAudit.swift \
    BindAll/Autocomplete/AutocompleteInsertion.swift \
    BindAll/Autocomplete/AutocompleteKeyPolicy.swift \
    BindAll/Autocomplete/InlineCompletion.swift \
    BindAll/Selection/TextDiff.swift \
    BindAll/Selection/EdgeWhitespace.swift \
    BindAll/Selection/ReplaceTarget.swift \
    BindAll/Proofread/ProofreadKeyPolicy.swift \
    Tests/Unit/*.swift \
    -o "$OUT"

"$OUT"
