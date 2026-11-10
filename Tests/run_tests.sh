#!/bin/bash
# Compiles the pure-logic sources together with the test runner and executes them.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/LogicTests"
swiftc -O \
    Bindly/Store/ActionKey.swift \
    Bindly/Store/PushToTalkKey.swift \
    Bindly/Store/Settings.swift \
    Bindly/Store/LanguageToolURL.swift \
    Bindly/Actions/MaskAISlopRule.swift \
    Bindly/Actions/MaskAISlop.swift \
    Bindly/Actions/KeyboardLayoutMap.swift \
    Bindly/Actions/TextTool.swift \
    Bindly/Store/AppPaths.swift \
    Bindly/Store/HistoryStore.swift \
    Bindly/Store/HistoryMenuTitle.swift \
    Bindly/Store/UsageLog.swift \
    Bindly/Engines/AIEngine.swift \
    Bindly/Engines/FallbackEngine.swift \
    Bindly/Engines/LanguageMatch.swift \
    Bindly/Proofread/TextIssue.swift \
    Bindly/Proofread/WordBoundary.swift \
    Bindly/Proofread/UnderlineGeometry.swift \
    Bindly/Proofread/IssueMerger.swift \
    Bindly/Proofread/ProofreadCache.swift \
    Bindly/Proofread/ProofreadLanguage.swift \
    Bindly/Proofread/RecheckPolicy.swift \
    Bindly/Proofread/ProofreadClickPolicy.swift \
    Bindly/Proofread/HiddenBreaks.swift \
    Bindly/Proofread/ProofreadSkips.swift \
    Bindly/Proofread/FixAll.swift \
    Bindly/Proofread/PersonalDictionary.swift \
    Bindly/Proofread/OfflineSpelling.swift \
    Bindly/Proofread/PreSendPolicy.swift \
    Bindly/Voice/HoldKeyPolicy.swift \
    Bindly/App/StatusIconTwinkle.swift \
    Bindly/Store/ShortcutConflicts.swift \
    Bindly/Store/SelectionCommand.swift \
    Bindly/Proofread/TextOccurrence.swift \
    Bindly/UI/PanelPlacement.swift \
    Bindly/UI/PanelWidth.swift \
    Bindly/UI/ResultMarkdown.swift \
    Bindly/Voice/AudioLevelMeter.swift \
    Bindly/Proofread/ListMarkers.swift \
    Bindly/Proofread/AppOffsetMap.swift \
    Bindly/Engines/TranslationLayout.swift \
    Bindly/Engines/LanguagePair.swift \
    Bindly/Store/AppLanguages.swift \
    Bindly/Engines/OCRParagraphs.swift \
    Bindly/Engines/DocumentLayout.swift \
    Bindly/UI/PopupTilePacker.swift \
    Bindly/Engines/LanguageToolEngine.swift \
    Bindly/LocalServer/LocalServerLayout.swift \
    Bindly/LocalServer/LocalServerPort.swift \
    Bindly/LocalServer/LocalServerRelease.swift \
    Bindly/LocalServer/LocalServerManifest.swift \
    Bindly/Autocomplete/AutocompleteEngine.swift \
    Bindly/Autocomplete/AutocompleteLearningStore.swift \
    Bindly/Autocomplete/UnigramLexicon.swift \
    Bindly/Autocomplete/ContextProbability.swift \
    Bindly/Autocomplete/LearnedWordAudit.swift \
    Bindly/Autocomplete/AutocompleteInsertion.swift \
    Bindly/Autocomplete/AutocompleteKeyPolicy.swift \
    Bindly/Autocomplete/InlineCompletion.swift \
    Bindly/Selection/TextDiff.swift \
    Bindly/Selection/EdgeWhitespace.swift \
    Bindly/Selection/FieldStarPolicy.swift \
    Bindly/Selection/ReplaceTarget.swift \
    Bindly/Proofread/ProofreadKeyPolicy.swift \
    Tests/Unit/*.swift \
    -o "$OUT"

"$OUT"
