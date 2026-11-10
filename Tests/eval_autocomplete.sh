#!/bin/bash
# Compiles and runs the autocomplete evaluator (Tests/eval_autocomplete.swift).
# Usage: Tests/eval_autocomplete.sh [variant] [store] [limit] [bigramSeed] [trigramSeed] [unigramSeed]
#   variant: baseline | context | semantic (default context)
#   store:   cold | warm | online | online-picks (default online -- the fair mode)
#   CORPUS=path runs one corpus; by default the chat, news and general sets run in turn.
set -euo pipefail
cd "$(dirname "$0")/.."

VARIANT="${1:-context}"
STORE="${2:-online}"
LIMIT="${3:-5}"
BIGRAM="${4:-Bindly/Autocomplete/ru_bigrams_ctx.txt}"
TRIGRAM="${5:-Bindly/Autocomplete/ru_trigrams.txt}"
UNIGRAM="${6:-Bindly/Autocomplete/ru_unigrams.txt}"

OUT="$(mktemp -d)/EvalAutocomplete"
swiftc -O \
    Bindly/Autocomplete/AutocompleteEngine.swift \
    Bindly/Autocomplete/AutocompleteLearningStore.swift \
    Bindly/Autocomplete/SemanticRanker.swift \
    Bindly/Autocomplete/UnigramLexicon.swift \
    Bindly/Store/AppPaths.swift \
    Tests/eval_autocomplete.swift \
    -o "$OUT"

if [ -n "${CORPUS:-}" ]; then
    CORPORA=("$CORPUS")
else
    CORPORA=(Tests/ru_eval_chat.txt Tests/ru_eval_news.txt Tests/ru_eval_corpus.txt)
fi
for c in "${CORPORA[@]}"; do
    "$OUT" "$c" "$VARIANT" "$STORE" "$LIMIT" "$BIGRAM" "$TRIGRAM" "$UNIGRAM"
    echo
done
