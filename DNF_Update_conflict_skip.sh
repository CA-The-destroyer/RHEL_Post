#!/usr/bin/env bash
# update-skip-conflicts.sh — auto-skip conflicts (now handles "conflicting requests")
set -euo pipefail

DryRun=false; DNF_ENABLE_REPOS=(); DNF_DISABLE_REPOS=(); EXTRA_EXCLUDES=(); DNF_SKIP_BROKEN=false
usage(){ cat <<'U'
Usage: update-skip-conflicts.sh [options]
  -DryRun                   Simulate only
  --enablerepo='glob'       Pass-through to dnf
  --disablerepo='glob'      Pass-through to dnf
  --extra-exclude='a,b,c'   Extra exclude globs
  --skip-broken             Add dnf --skip-broken
U
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    -DryRun|--DryRun|--dry-run) DryRun=true ;;
    --enablerepo=*) DNF_ENABLE_REPOS+=("${arg#*=}") ;;
    --disablerepo=*) DNF_DISABLE_REPOS+=("${arg#*=}") ;;
    --extra-exclude=*) IFS=',' read -r -a _t <<< "${arg#*=}"; for p in "${_t[@]}"; do [[ -n $p ]]&&EXTRA_EXCLUDES+=("$p"); done ;;
    --skip-broken) DNF_SKIP_BROKEN=true ;;
    *) echo "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

DNF_ARGS=(); for r in "${DNF_ENABLE_REPOS[@]}"; do DNF_ARGS+=( "--enablerepo=$r" ); done
for r in "${DNF_DISABLE_REPOS[@]}"; do DNF_ARGS+=( "--disablerepo=$r" ); done

echo "=== Detecting conflicts (dry run) ==="
conflicts_raw=$(dnf update --assumeno -y "${DNF_ARGS[@]}" 2>&1 || true)

# Collect basenames from common conflict phrasings, including the generic solver error
mapfile -t conflict_basenames < <(
  echo "$conflicts_raw" |
  grep -E 'cannot install both|conflicts with|conflicting requests|problem with|package .* is filtered out by modular filtering' |
  grep -oE '([[:alnum:]_.+-]+)-[0-9][^[:space:]]*' |
  cut -d'-' -f1 |
  sort -u
)

# Heuristic: kernel pairs must match; if solver mentioned them anywhere, exclude both
if echo "$conflicts_raw" | grep -qiE '\bkernel(-modules)?\b'; then
  conflict_basenames+=("kernel" "kernel-modules")
fi

# Build exclude list
EXCLUDES=()
if ((${#conflict_basenames[@]} > 0)); then
  echo "Detected conflicting families:"
  for n in $(printf "%s\n" "${conflict_basenames[@]}" | sort -u); do
    echo "  - ${n}*"
    EXCLUDES+=( "--exclude=${n}*" )
  done
else
  echo "No conflicts detected."
fi

# Extra excludes from CLI
for p in "${EXTRA_EXCLUDES[@]}"; do
  echo "Adding user exclude: $p"
  EXCLUDES+=( "--exclude=${p}" )
done

$DNF_SKIP_BROKEN && EXCLUDES+=( "--skip-broken" )

if $DryRun; then
  printf "[DryRun] Would run: sudo dnf update -y"
  printf " %q" "${DNF_ARGS[@]}" "${EXCLUDES[@]}"; echo
  exit 0
fi

echo "=== Running update (skipping detected conflicts) ==="
sudo dnf update -y "${DNF_ARGS[@]}" "${EXCLUDES[@]}"
echo "=== Update complete ==="
