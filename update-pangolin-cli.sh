#!/usr/bin/env bash
set -euo pipefail

# Script CLI de mise à jour Pangolin (Linux, sans interface graphique)
# Prérequis: docker, docker compose (ou docker-compose)

# Utilisation
usage() {
  cat <<'EOF'
Usage: update-pangolin-cli.sh [options]

Options:
  --compose PATH             Chemin vers docker-compose.yml
  --traefik-config PATH      Chemin vers traefik_config.yml
  --config-dir PATH          Dossier de configuration à sauvegarder
  --backup-root PATH         Dossier de destination pour la sauvegarde
  --pangolin-version VER     Version d'image Pangolin (ex: 1.7.3)
  --gerbil-version VER       Version d'image Gerbil (ex: 1.2.1)
  --traefik-version VER      Version d'image Traefik (ex: v3.4.0)
  --badger-version VER       Version du plugin Badger (ex: v1.2.0)
  --down/--no-down           Exécuter (ou non) docker compose down (défaut: --down)
  --pull/--no-pull           Exécuter (ou non) docker compose pull (défaut: --pull)
  --up/--no-up               Exécuter (ou non) docker compose up -d (défaut: --up)
  -y, --assume-yes           Ne pas poser de questions, utiliser les valeurs fournies
  -h, --help                 Afficher cette aide

Exemples:
  ./update-pangolin-cli.sh \
    --compose /opt/pangolin/docker-compose.yml \
    --traefik-config /opt/pangolin/config/traefik/traefik_config.yml \
    --config-dir /opt/pangolin/config \
    --backup-root /opt/backups \
    --pangolin-version 1.7.3 --gerbil-version 1.2.1 --traefik-version v3.4.0 --badger-version v1.2.0
EOF
}

# Vérifications de dépendances
need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Commande requise introuvable: $1" >&2
    exit 1
  fi
}

need_cmd docker

# Détecter docker compose
DOCKER_COMPOSE_BIN=""
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE_BIN="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE_BIN="docker-compose"
else
  echo "docker compose / docker-compose introuvable. Veuillez l'installer." >&2
  exit 1
fi

# Defaults
COMPOSE_PATH=""
TRAEFIK_CONFIG_PATH=""
CONFIG_DIR=""
BACKUP_ROOT=""
PANGOLIN_VER=""
GERBIL_VER=""
TRAEFIK_VER=""
BADGER_VER=""
DO_DOWN=true
DO_PULL=true
DO_UP=true
ASSUME_YES=false

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose) COMPOSE_PATH="$2"; shift 2;;
    --traefik-config) TRAEFIK_CONFIG_PATH="$2"; shift 2;;
    --config-dir) CONFIG_DIR="$2"; shift 2;;
    --backup-root) BACKUP_ROOT="$2"; shift 2;;
    --pangolin-version) PANGOLIN_VER="$2"; shift 2;;
    --gerbil-version) GERBIL_VER="$2"; shift 2;;
    --traefik-version) TRAEFIK_VER="$2"; shift 2;;
    --badger-version) BADGER_VER="$2"; shift 2;;
    --down) DO_DOWN=true; shift;;
    --no-down) DO_DOWN=false; shift;;
    --pull) DO_PULL=true; shift;;
    --no-pull) DO_PULL=false; shift;;
    --up) DO_UP=true; shift;;
    --no-up) DO_UP=false; shift;;
    -y|--assume-yes) ASSUME_YES=true; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Option inconnue: $1" >&2; usage; exit 1;;
  esac
done

stamp() { date '+%H:%M:%S'; }
log() { echo "$(stamp) - $*"; }

LOGFILE="$(mktemp -t pangolin_update_cli_XXXX).log"
exec > >(tee -a "$LOGFILE") 2>&1

# Fonctions
prompt_if_empty() {
  local varname="$1"; local prompt="$2"
  local current_value
  current_value=$(eval echo "\${$varname}")
  if [[ -z "$current_value" && "$ASSUME_YES" != true ]]; then
    read -r -p "$prompt" current_value
    eval "$varname=\"$current_value\""
  fi
}

require_path() {
  local p="$1"; local desc="$2"
  if [[ -z "$p" ]]; then
    echo "$desc non fourni." >&2; exit 1
  fi
}

backup_config() {
  local src="$1" dst_root="$2"
  mkdir -p "$dst_root"
  local ts
  ts="$(date '+%Y%m%d_%H%M%S')"
  local dest
  dest="${dst_root%/}/config_backup_${ts}"
  log "Sauvegarde de $src vers $dest..."
  cp -a "$src" "$dest"
  log "Sauvegarde terminée: $dest"
}

update_compose_file() {
  local path="$1"; local pang="$2"; local gerb="$3"; local traef="$4"
  log "Mise à jour des images dans $path..."
  sed -E -i "s|(^[[:space:]]*image:[[:space:]]*)fosrl/pangolin:[^[:space:]]+|\1fosrl/pangolin:${pang}|" "$path"
  sed -E -i "s|(^[[:space:]]*image:[[:space:]]*)fosrl/gerbil:[^[:space:]]+|\1fosrl/gerbil:${gerb}|" "$path"
  sed -E -i "s|(^[[:space:]]*image:[[:space:]]*)traefik:[^[:space:]]+|\1traefik:${traef}|" "$path"
  log "docker-compose.yml mis à jour."
}

update_badger_version() {
  local path="$1"; local badger="$2"
  log "Mise à jour de Badger dans $path..."
  local tmp
  tmp="$(mktemp)"
  awk -v badger="${badger}" '
  BEGIN{in_badger=0}
  {
    if ($0 ~ /^[[:space:]]*badger:[[:space:]]*$/) { in_badger=1; print; next }
    if (in_badger==1 && $0 ~ /^[[:space:]]*version:[[:space:]]*/) {
      match($0,/^[[:space:]]*/)
      pre=substr($0,1,RLENGTH)
      print pre "version: " badger
      in_badger=2
      next
    }
    if (in_badger==1 && $0 ~ /^[[:space:]]*[A-Za-z0-9_]+:[[:space:]]*$/) { in_badger=0; print; next }
    print
  }' "$path" > "$tmp"
  mv "$tmp" "$path"
  log "traefik_config.yml mis à jour."
}

compose_run() {
  local file="$1"; shift
  local dir
  dir="$(dirname "$file")"
  (cd "$dir" && ${DOCKER_COMPOSE_BIN} "$@")
}

# Renseigner les valeurs manquantes
prompt_if_empty COMPOSE_PATH "Chemin docker-compose.yml: "
prompt_if_empty TRAEFIK_CONFIG_PATH "Chemin traefik_config.yml: "
prompt_if_empty CONFIG_DIR "Dossier de configuration à sauvegarder: "
prompt_if_empty BACKUP_ROOT "Dossier de destination pour la sauvegarde: "
prompt_if_empty PANGOLIN_VER "Version Pangolin (ex: 1.7.3): "
prompt_if_empty GERBIL_VER "Version Gerbil (ex: 1.2.1): "
prompt_if_empty TRAEFIK_VER "Version Traefik (ex: v3.4.0): "
prompt_if_empty BADGER_VER "Version Badger (ex: v1.2.0): "

# Validation
require_path "$COMPOSE_PATH" "docker-compose.yml"
require_path "$TRAEFIK_CONFIG_PATH" "traefik_config.yml"
require_path "$CONFIG_DIR" "Dossier de configuration"
require_path "$BACKUP_ROOT" "Dossier de sauvegarde"

log "Démarrage de la mise à jour Pangolin (CLI)"

backup_config "$CONFIG_DIR" "$BACKUP_ROOT"
update_compose_file "$COMPOSE_PATH" "$PANGOLIN_VER" "$GERBIL_VER" "$TRAEFIK_VER"
update_badger_version "$TRAEFIK_CONFIG_PATH" "$BADGER_VER"

if [[ "$DO_DOWN" == true ]]; then
  log "Arrêt du stack (compose down)"; compose_run "$COMPOSE_PATH" down || true
fi
if [[ "$DO_PULL" == true ]]; then
  log "Téléchargement des images (compose pull)"; compose_run "$COMPOSE_PATH" pull
fi
if [[ "$DO_UP" == true ]]; then
  log "Démarrage du stack (compose up -d)"; compose_run "$COMPOSE_PATH" up -d
fi

log "Mise à jour terminée. Journal: $LOGFILE"
log "Vérifiez votre dashboard Pangolin, l'accessibilité des sites et les tunnels (si Gerbil)."

exit 0