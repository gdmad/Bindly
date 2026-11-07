#!/bin/bash
# Compiles the pure-logic sources together with the test runner and executes them.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/LogicTests"
swiftc -O \
    BindAll/Store/ActionKey.swift \
    BindAll/Store/PushToTalkKey.swift \
    BindAll/Store/Settings.swift \
    BindAll/Actions/MaskAISlopRule.swift \
    BindAll/Actions/MaskAISlop.swift \
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
    BindAll/Proofread/TextOccurrence.swift \
    BindAll/UI/PanelPlacement.swift \
    BindAll/Voice/AudioLevelMeter.swift \
    BindAll/Proofread/ListMarkers.swift \
    BindAll/Proofread/AppOffsetMap.swift \
    BindAll/Engines/TranslationLayout.swift \
    BindAll/Engines/OCRParagraphs.swift \
    BindAll/UI/PopupTilePacker.swift \
    BindAll/Engines/LanguageToolEngine.swift \
    BindAll/Autocomplete/AutocompleteEngine.swift \
    BindAll/Autocomplete/AutocompleteLearningStore.swift \
    BindAll/Autocomplete/LearnedWordAudit.swift \
    BindAll/Autocomplete/AutocompleteInsertion.swift \
    BindAll/Autocomplete/AutocompleteKeyPolicy.swift \
    BindAll/Autocomplete/InlineCompletion.swift \
    BindAll/Selection/TextDiff.swift \
    BindAll/Proofread/ProofreadKeyPolicy.swift \
    Tests/Unit/*.swift \
    -o "$OUT"

"$OUT"
