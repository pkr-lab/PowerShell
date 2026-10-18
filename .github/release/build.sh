#!/usr/bin/env bash
set -euo pipefail

version="$1"
stage="dist/stage"

rm -rf "${stage}"
mkdir -p "${stage}"
git archive HEAD . ':(exclude).github' ':(exclude).githooks' ':(exclude).idea' | tar -x -C "${stage}"
(cd "${stage}" && zip -q -r "../PowerShell-v${version}.zip" .)
rm -rf "${stage}"
