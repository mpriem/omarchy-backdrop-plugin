#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PYTHONDONTWRITEBYTECODE=1
node tests/policy.test.cjs
python3 -m unittest discover -s tests -p '*_test.py'
bash -n install.sh
# Arch also packages an unrelated Qt 5 qmlformat at /usr/bin/qmlformat.
formatter=${QMLFORMAT:-/usr/lib/qt6/bin/qmlformat}
for file in ./*.qml; do "$formatter" "$file" >/dev/null; done
python3 -c 'import json; json.load(open("manifest.json"))'
omarchy-plugin-validate .
git diff --check
