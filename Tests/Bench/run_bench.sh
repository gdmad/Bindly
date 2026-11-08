#!/bin/bash
# Apple's built-in text features against BindAll's current ones; writes .build/bench/report.md.
# Sends the fixed test sentences (Corpus.swift, nothing of yours) to LanguageTool servers.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build/bench
swiftc -O Tests/Bench/*.swift BindAll/Engines/OCRParagraphs.swift -o .build/bench/bench 2>&1 | grep -v warning || true
.build/bench/bench .build/bench/report.md
