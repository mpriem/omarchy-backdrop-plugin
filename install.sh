#!/usr/bin/env bash
# Stage and validate a bounded payload before handing off the shared IPC target.
set -euo pipefail
id=backgrounds
src=$(cd "$(dirname "$0")" && pwd)
# Omarchy's runtime paths currently use HOME, regardless of XDG_CONFIG_HOME.
if [[ ${XDG_CONFIG_HOME:-$HOME/.config} != "$HOME/.config" ]]; then
  echo 'backgrounds: Omarchy requires installation under $HOME/.config' >&2
  exit 1
fi
parent=$HOME/.config/omarchy/plugins
dst=$parent/$id
mkdir -p "$parent"
[[ ! -L $dst ]] || { echo 'backgrounds: destination must not be a symlink' >&2; exit 1; }
stage=$(mktemp -d "$parent/.backgrounds-stage.XXXXXX")
backup=$stage/previous
payload=$stage/payload
mkdir "$payload"
handoff=false
replaced=false
had_previous=false
stock_enabled=false
plugin_enabled=false

finish() {
  local result=$?
  trap - EXIT INT TERM
  if (( result != 0 )) && $handoff; then
    echo 'backgrounds: activation failed; restoring the previous installation and enabled state' >&2
    # Best effort continues through each step, and reports any restoration failure.
    omarchy plugin disable "$id" || echo 'backgrounds: rollback could not disable replacement' >&2
    if $replaced; then
      rm -rf -- "$dst"
    fi
    if $had_previous; then
      if ! mv -- "$backup" "$dst"; then
        echo "backgrounds: previous files retained at $backup; manual restoration required" >&2
        exit "$result"
      fi
    fi
    omarchy-shell shell rescanPlugins || echo 'backgrounds: rollback rescan failed' >&2
    if $plugin_enabled; then
      omarchy plugin enable "$id" || echo 'backgrounds: rollback could not re-enable previous plugin' >&2
    fi
    if $stock_enabled; then
      omarchy plugin enable omarchy.background || echo 'backgrounds: rollback could not re-enable stock background' >&2
    fi
  fi
  rm -rf -- "$stage"
  exit "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

runtime=(Background.qml BackgroundScreen.qml BackgroundCatalog.qml ConfigStore.qml
  Panel.qml ChipRow.qml PickerList.qml Drum.qml IntervalWheels.qml PoolMark.qml
  RevealMask.qml TransitionSection.qml Config.js Selection.js catalog.py manifest.json LICENSE)
for file in "${runtime[@]}"; do cp -P -- "$src/$file" "$payload/$file"; done
omarchy-plugin-validate "$payload"
echo 'backgrounds: staged payload validated'
state=$(omarchy plugin list --json)
stock_enabled=$(jq -r 'any(.[]; .id == "omarchy.background" and .enabled)' <<<"$state")
plugin_enabled=$(jq -r 'any(.[]; .id == "backgrounds" and .enabled)' <<<"$state")
# Require actual boolean output before touching the enabled state.
[[ $stock_enabled == true || $stock_enabled == false ]]
[[ $plugin_enabled == true || $plugin_enabled == false ]]
handoff=true
if $plugin_enabled; then omarchy plugin disable "$id"; fi
# Disabling a clone can restore its stock source, even if it was disabled before.
omarchy plugin disable omarchy.background
if [[ -e $dst ]]; then
  mv -- "$dst" "$backup"
  had_previous=true
fi
mv -- "$payload" "$dst"
replaced=true
omarchy-shell shell rescanPlugins
# Rescanning is asynchronous on the supported host. Wait for discovery before
# enablement, and confirm that the replacement IPC service actually starts.
wait_for_plugin() {
  local attempt
  for attempt in {1..20}; do
    if omarchy plugin list --json | jq -e 'any(.[]; .id == "backgrounds")' >/dev/null; then return 0; fi
    sleep 0.1
  done
  echo 'backgrounds: plugin discovery timed out' >&2
  return 1
}
wait_for_service() {
  local attempt
  for attempt in {1..20}; do
    if OMARCHY_SHELL_IPC_TIMEOUT=500ms omarchy-shell background status 2>/dev/null |
      jq -e 'has("mode") and has("screens") and has("images")' >/dev/null 2>&1; then return 0; fi
    sleep 0.1
  done
  echo 'backgrounds: replacement service did not become ready' >&2
  return 1
}
wait_for_plugin
omarchy plugin enable "$id"
wait_for_service
echo "$id: installed and enabled at $dst"
