#!/usr/bin/env bash
#
# prune-deleted-providers.sh
#
# Re-applies the provider-strip-down after an upstream merge reintroduces
# provider directories or manifest entries. Run from the repo root after
# resolving the non-provider parts of the merge:
#
#   ./scripts/prune-deleted-providers.sh
#
# The script:
#   1. Deletes the known deleted-provider source and test directories.
#   2. Fails loudly if a deleted-provider name still appears in a key manifest
#      or kept source/test file (indicating manual follow-up is needed).
#   3. Leaves unrelated merge conflicts untouched.

set -euo pipefail

cd "$(dirname "$0")/.."

DELETED_PROVIDERS=(
  AlibabaProvider
  AmazonBedrockProvider
  AssemblyAIProvider
  AzureProvider
  BasetenProvider
  BlackForestLabsProvider
  ByteDanceProvider
  CerebrasProvider
  CohereProvider
  DeepInfraProvider
  DeepSeekProvider
  DeepgramProvider
  FalProvider
  FireworksProvider
  GladiaProvider
  GroqProvider
  HuggingFaceProvider
  HumeProvider
  KlingAIProvider
  LMNTProvider
  LumaProvider
  MoonshotAIProvider
  OpenResponsesProvider
  ProdiaProvider
  ReplicateProvider
  RevAIProvider
  TogetherAIProvider
)

echo "==> Removing deleted provider directories (if reintroduced)"
for provider in "${DELETED_PROVIDERS[@]}"; do
  if [ -d "Sources/${provider}" ]; then
    echo "    rm Sources/${provider}"
    rm -rf "Sources/${provider}"
  fi
  if [ -d "Tests/${provider}Tests" ]; then
    echo "    rm Tests/${provider}Tests"
    rm -rf "Tests/${provider}Tests"
  fi
done

echo "==> Checking that deleted provider names no longer appear in key files"
FAIL=0
CHECK_PATHS=(
  Package.swift
  .spi.yml
  examples/Package.swift
  Sources
  Tests
)

for provider in "${DELETED_PROVIDERS[@]}"; do
  for path in "${CHECK_PATHS[@]}"; do
    if [ -e "$path" ]; then
      if grep -RIn --exclude-dir=.build "$provider" "$path" >/dev/null 2>&1; then
        echo "    FAIL: '$provider' still referenced in $path"
        grep -RIn --exclude-dir=.build "$provider" "$path" | head -5
        FAIL=1
      fi
    fi
  done
done

if [ "$FAIL" -ne 0 ]; then
  echo
  echo "==> Some deleted-provider references remain. Resolve manually, then rerun."
  exit 1
fi

echo "==> OK: deleted providers are fully removed."
