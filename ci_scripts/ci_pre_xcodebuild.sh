#!/bin/sh
# Xcode Cloud — pre-xcodebuild script
# Runs before every build/test/archive action.

set -e

echo "ci_pre_xcodebuild: CI=$CI, CI_WORKFLOW=$CI_WORKFLOW, CI_BUILD_NUMBER=$CI_BUILD_NUMBER"
