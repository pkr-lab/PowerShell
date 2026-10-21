#!/usr/bin/env bash
set -euo pipefail

QUELLE="${QUELLE:-/opt/git/mein-projekt}"
ZIEL="${ZIEL:-/opt/stacks/mein-projekt}"
BRANCH="${BRANCH:-main}"
AUSLOESER="${AUSLOESER:-commit}"
TAG_MUSTER="${TAG_MUSTER:-v*}"
VERSIONSDATEI="${VERSIONSDATEI:-VERSION}"
BEFEHL="${BEFEHL-docker compose up -d}"
AUSNAHMEN="${AUSNAHMEN:-}"
LOESCHEN="${LOESCHEN:-false}"
STAND_DATEI="${STAND_DATEI:-$QUELLE/.git/git-pull-deploy.stand}"

log() { echo "[git-pull-deploy] $(date '+%F %T') $*" >&2; }

usage() {
  cat <<'USAGE'
Usage: git-pull-deploy.sh [--check] [--force]

Holt mit git pull den neuesten Stand von BRANCH nach QUELLE, kopiert den Inhalt ohne .git
nach ZIEL und führt dort BEFEHL aus. Das passiert nur, wenn es seit dem letzten erfolgreichen
Lauf eine neue Version gibt:

  AUSLOESER=commit   jeder neue Commit auf BRANCH (Standard)
  AUSLOESER=tag      ein neuer Tag nach TAG_MUSTER (z. B. v1.4.0 von semantic-release)
  AUSLOESER=datei    der Inhalt von VERSIONSDATEI hat sich geändert

Alle Variablen oben im Skript lassen sich auch per Umgebung setzen.

  --check     nur prüfen, nichts ziehen oder kopieren (Exit 0 = neue Version, 1 = keine)
  --force     auch ohne neue Version ziehen, kopieren und BEFEHL ausführen
  -h, --help  diese Hilfe
USAGE
}

CHECK=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1 ;;
    --force) FORCE=1 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

for tool in git rsync flock realpath; do
  command -v "$tool" >/dev/null || { log "${tool} fehlt"; exit 1; }
done

if [ ! -d "$QUELLE/.git" ]; then
  log "${QUELLE} ist kein Git-Repo, einmalig: git clone <URL> ${QUELLE}"
  exit 1
fi

quelle_abs=$(realpath -m "$QUELLE")
ziel_abs=$(realpath -m "$ZIEL")
if [ "$ziel_abs" = / ] || [[ "$ziel_abs/" == "$quelle_abs/"* || "$quelle_abs/" == "$ziel_abs/"* ]]; then
  log "ZIEL=${ZIEL} ungültig: darf nicht / sein und QUELLE weder enthalten noch darin liegen"
  exit 1
fi

exec 9>"$QUELLE/.git/git-pull-deploy.lock"
if ! flock -n 9; then
  log "läuft bereits, Abbruch"
  exit 0
fi

trap 'log "Fehler in Zeile ${LINENO}, Stand wird nicht als ausgerollt markiert"' ERR

version_von() {
  case "$AUSLOESER" in
    commit) git -C "$QUELLE" rev-parse --verify --quiet "$1^{commit}" ;;
    tag) git -C "$QUELLE" describe --tags --abbrev=0 --match "$TAG_MUSTER" "$1" 2>/dev/null ;;
    datei) git -C "$QUELLE" show "$1:$VERSIONSDATEI" 2>/dev/null | tr -d '[:space:]' ;;
    *) return 1 ;;
  esac
}

git -C "$QUELLE" fetch --quiet --force --tags origin "+refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}"

if ! neu=$(version_von "origin/${BRANCH}") || [ -z "$neu" ]; then
  log "keine Version auf origin/${BRANCH} gefunden (AUSLOESER=${AUSLOESER}, erlaubt: commit, tag, datei)"
  exit 1
fi
alt=$(cat "$STAND_DATEI" 2>/dev/null || true)

if [ "$neu" != "$alt" ]; then
  log "neue Version: ${alt:-noch nichts ausgerollt} -> ${neu}"
elif [ "$FORCE" -eq 1 ]; then
  log "keine neue Version (${neu}), wegen --force trotzdem"
else
  log "keine neue Version (${neu})"
  if [ "$CHECK" -eq 1 ]; then
    exit 1
  fi
  exit 0
fi

if [ "$CHECK" -eq 1 ]; then
  exit 0
fi

git -C "$QUELLE" checkout --quiet "$BRANCH"
git -C "$QUELLE" pull --quiet --ff-only origin "$BRANCH"
if [ "$AUSLOESER" = tag ]; then
  git -C "$QUELLE" checkout --quiet --detach "refs/tags/${neu}"
else
  neu=$(version_von HEAD)
fi

rsync_args=(-a --exclude=.git)
read -r -a ausnahmen <<<"$AUSNAHMEN"
for muster in "${ausnahmen[@]}"; do
  rsync_args+=("--exclude=${muster}")
done
if [ "$LOESCHEN" = true ]; then
  rsync_args+=(--delete)
fi

mkdir -p "$ZIEL"
rsync "${rsync_args[@]}" "$QUELLE"/ "$ZIEL"/
log "nach ${ZIEL} kopiert"

if [ -n "$BEFEHL" ]; then
  log "führe in ${ZIEL} aus: ${BEFEHL}"
  (cd "$ZIEL" && bash -c "$BEFEHL") 9>&-
fi

printf '%s\n' "$neu" >"$STAND_DATEI"
log "fertig, ausgerollt: ${neu}"