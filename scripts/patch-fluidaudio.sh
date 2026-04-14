#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <derived-data-path>" >&2
    exit 1
fi

derived_data_path="$1"
target_file="$derived_data_path/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/ASR/Streaming/StreamingAsrManager.swift"

if [[ ! -f "$target_file" ]]; then
    echo "FluidAudio checkout not found at $target_file" >&2
    exit 1
fi

if rg -q "unsafeAsrManager" "$target_file"; then
    echo "FluidAudio Swift 6 streaming patch already applied"
    exit 0
fi

perl -0pi -e 's/if let asrManager = asrManager \{\n            try await asrManager\.resetDecoderState\(for: audioSource\)\n        \}/if let asrManager = asrManager {\n            nonisolated(unsafe) let unsafeAsrManager = asrManager\n            try await unsafeAsrManager.resetDecoderState(for: audioSource)\n        }/g' "$target_file"

perl -0pi -e 's/guard let asrManager = asrManager else \{ return \}\n\n        do \{/guard let asrManager = asrManager else { return }\n        nonisolated(unsafe) let unsafeAsrManager = asrManager\n\n        do {/g' "$target_file"

perl -0pi -e 's/let \(tokens, timestamps, confidences, _\) = try await asrManager\.transcribeStreamingChunk\(/let (tokens, timestamps, confidences, _) = try await unsafeAsrManager.transcribeStreamingChunk(/g' "$target_file"

perl -0pi -e 's/if let asrManager = asrManager \{\n            do \{\n                try await asrManager\.resetDecoderState\(for: audioSource\)/if let asrManager = asrManager {\n            nonisolated(unsafe) let unsafeAsrManager = asrManager\n            do {\n                try await unsafeAsrManager.resetDecoderState(for: audioSource)/g' "$target_file"

if ! rg -q "unsafeAsrManager" "$target_file"; then
    echo "Failed to apply FluidAudio Swift 6 streaming patch" >&2
    exit 1
fi

echo "Applied FluidAudio Swift 6 streaming patch"
