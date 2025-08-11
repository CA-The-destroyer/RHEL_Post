#!/usr/bin/env bash
#------------------------------------------------------------------------------
# update-skip-conflicts.sh
#
# Purpose:
#   Safely update RHEL/CentOS/Fedora systems while AUTOMATICALLY skipping any
#   detected package conflicts (e.g., Nexus vs AppStream .NET). No guessing.
#
# How it works:
#   1) Dry-run: `dnf update --assumeno` to discover conflicts
#   2) Parse conflicting package names -> build exclude list
#   3) Run a real `dnf update` excluding only those names
#
# Key features:
#   - -DryRun        : simulate actions; print the exact dnf command that would run
#   - --enablerepo   : pass-through to dnf (glob allowed), can be used multiple times
#   - --disablerepo  : pass-through to dnf (glob allowed), can be used multiple times
#   - --extra-exclude: comma-separated patterns to exclude in addition to detected ones
#   - --skip-broken  : add dnf’s --skip-broken for noisy environments
#
# Examples:
#   ./update-skip-conflicts.sh -DryRun
#   ./update-skip-conflicts.sh
#   ./update-skip-conflicts.sh --disablerepo='nexus*'
#   ./update-skip-conflicts.sh --enablerepo='nexus*' --disablerepo='rhel-*-appstream*'
#   ./update-skip-conflicts.sh --extra-exclude='dotnet*,aspnetcore*' -DryRun
#   ./update-skip-conflicts.sh --skip-broken
#
# Exit codes:
#   0  success (or dry-run success)
#   1  unexpected failure
#
# Notes:
#   - Idempotent: only affects this run; no permanent repo or config changes.
#   - Tested on RHEL 9.x. Requires `dnf`.
#------------------------------------------------------------------------------

set -euo pipefail

#----------------------------
# Arg parsing
#----------------------------
DryRun=false
DNF_ENABLE_REPOS=()
DNF_DISABLE_REPOS=()
EXTRA_EXCLUDES=()
DNF_SKIP_BROKEN=false

usage() {
  cat <<'USAGE'
Usage: update-skip-conflicts.sh [options]

Options:
  -DryRun                   Simulate and print the final dnf command; make no changes
  --enablerepo='glob'       Enable a repo (can be used multiple times)
  --disablerepo='glob'      Disable a repo (can be used multiple times)
  --extra-exclude='a,b,c'   Extra comma-separated exclude patterns
  --skip-broken             Add dnf's --skip-broken to the final update

Examples:
  ./update-skip-conflicts.sh -DryRun
  ./update-skip-conflicts.sh --disablerepo='nexus*'
  ./update-skip-conflicts.sh --extra-exclude='dotnet*,aspnetcore*'
USAGE
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    -DryRun|--DryRun|--dry-run) DryRun=true ;;
    --enablerepo=*)
      DNF_ENABLE_REPOS+=("${arg#*=}")
      ;;
    --disablerepo=*)
      DNF_DISABLE_REPOS+=("${arg#*=}")
      ;;
    --extra-exclude=*)
      IFS=',' read -r -a _tmp <<< "${arg#*=}"
      for p in "${_tmp[@]}"; do
        [[ -n "$p" ]] && EXTRA_EXCLUDES+=("$p")
      done
      ;;
    --skip-broken)
      DNF_SKIP_BROKEN=true
      ;;
    *)
      echo "Unknown option: $arg" >&2
      usage
      exit 1
      ;;
  esac
done

# Build pass-through args for dnf
DNF_ARGS=()
for r in "${DNF_ENABLE_REPOS[@]}";  do DNF_ARGS+=( "--enablerepo=$r" ); done
for r in "${DNF_DISABLE_REPOS[@]}"; do DNF_ARGS+=( "--disablerepo=$r" ); done

#----------------------------
# Step 1: Dry-run to detect conflicts
#----------------------------
echo "=== Detecting conflicts with dry run ==="
# --assumeno prints planned transaction, including conflicts, without changing the system
conflicts_raw=$(dnf update --assumeno -y "${DNF_ARGS[@]}" 2>&1 || true)

# Extract NEVRA-like tokens (pkgname-version...) and reduce to base names (before first '-')
# We also look for lines that include common conflict phrases.
readarray -t conflict_basenames < <(
  echo "$conflicts_raw" |
  grep -E 'cannot install both|conflicts with|package .* is filtered out by modular filtering' |
  grep -oE '([[:alnum:]_.+-]+)-[0-9][^[:space:]]*' |
  sed 's/\s\+$//' |
  cut -d'-' -f1 |
  sort -u
)

#----------------------------
# Step 2: Build exclude list
#----------------------------
EXCLUDES=()
if ((${#conflict_basenames[@]} > 0)); then
  echo "Detected conflicting families:"
  for n in "${conflict_basenames[@]}"; do
    echo "  - ${n}*"
    EXCLUDES+=( "--exclude=${n}*" )
  done
else
  echo "No conflicts detected in dry run."
fi

# Add any extra excludes provided by the user
if ((${#EXTRA_EXCLUDES[@]} > 0)); then
  echo "Adding user-specified extra excludes:"
  for p in "${EXTRA_EXCLUDES[@]}"; do
    echo "  - ${p}"
    EXCLUDES+=( "--exclude=${p}" )
  done
fi

# Optional skip-broken
if $DNF_SKIP_BROKEN; then
  EXCLUDES+=( "--skip-broken" )
fi

#----------------------------
# Step 3: Real update (or DryRun print)
#----------------------------
if $DryRun; then
  # Show exactly what would run
  printf "[DryRun] Would run: sudo dnf update -y"
  for a in "${DNF_ARGS[@]}"; do printf " %q" "$a"; done
  for a in "${EXCLUDES[@]}"; do printf " %q" "$a"; done
  echo
  exit 0
else
  echo "=== Running update while excluding detected conflicts ==="
  sudo dnf update -y "${DNF_ARGS[@]}" "${EXCLUDES[@]}"
  echo "=== Update complete ==="
fi
