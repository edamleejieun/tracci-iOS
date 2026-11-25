#!/usr/bin/env bash
# Local / CI gate for DI + package + large-file architecture tests.
# Usage: ./scripts/run-architecture-gates.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
SCHEME="${SCHEME:-Tracci}"
PROJECT="${PROJECT:-Tracci.xcodeproj}"

echo "==> Architecture gates (DependencyInjectionArchitectureTests + brand render smoke)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "$DESTINATION" \
  -only-testing:TracciTests/DependencyInjectionArchitectureTests \
  -only-testing:TracciTests/BrandRenderChecksTests \
  test

echo "==> Architecture gates passed"
