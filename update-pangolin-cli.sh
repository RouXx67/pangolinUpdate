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
  --auto-discover            Tenter de découvrir automatiquement les chemins (compose/config/traefik)
  --search-root PATH         Racine de recherche pour --auto-discover (par défaut: racines communes)
  -y, --assume-yes           Ne pas poser de questions, utiliser les valeurs fournies
  -h, --help                 Afficher cette aide

Exemples:
  ./update-pangolin-cli.sh \
    --compose /srv/pangolin/docker-compose.yml \
    --traefik-config /srv/pangolin/config/traefik/traefik_config.yml \
    --config-dir /srv/pangolin/config \
    --backup-root /srv/backups \
    --pangolin-version 1.7.3 --gerbil-version 1.2.1 --traefik-version v3.4.0 --badger-version v1.2.0

  ./update-pangolin-cli.sh --auto-discover --backup-root /srv/backups
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
AUTO_DISCOVER=false
SEARCH_ROOT=""

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
    --auto-discover) AUTO_DISCOVER=true; shift;;
    --search-root) SEARCH_ROOT="$2"; shift 2;;
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

choose_from_list() {
  # $1: name, $2..: items
  local name="$1"; shift
  local items=("$@")
  if [[ ${#items[@]} -eq 0 ]]; then echo ""; return 0; fi
  if [[ "$ASSUME_YES" == true ]]; then echo "${items[0]}"; return 0; fi
  echo "Plusieurs candidats pour $name :"
  local i=1
  for it in "${items[@]}"; do
    echo "  [$i] $it"
    ((i++))
  done
  read -r -p "Choisissez [1-${#items[@]}] (défaut 1): " sel
  if [[ -z "$sel" ]]; then sel=1; fi
  if ! [[ "$sel" =~ ^[0-9]+$ ]] || [[ "$sel" -lt 1 ]] || [[ "$sel" -gt ${#items[@]} ]]; then sel=1; fi
  echo "${items[$((sel-1))]}"
}

discover_paths() {
  log "Auto-discovery des chemins en cours..."
  local roots=()
  if [[ -n "$SEARCH_ROOT" && -d "$SEARCH_ROOT" ]]; then
    roots+=("$SEARCH_ROOT")
  else
    [[ -d "/srv" ]] && roots+=("/srv")
    [[ -d "/opt" ]] && roots+=("/opt")
    [[ -d "/var" ]] && roots+=("/var")
    [[ -d "/etc" ]] && roots+=("/etc")
    # Ajouter tous les /home/* existants
    for h in /home/*; do [[ -d "$h" ]] && roots+=("$h"); done
    [[ -d "/root" ]] && roots+=("/root")
  fi

  local compose_candidates=()
  for r in "${roots[@]}"; do
    log "Recherche de docker-compose dans: $r"
    while IFS= read -r f; do compose_candidates+=("$f"); done < <(find "$r" -maxdepth 5 -type f \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yml' -o -name 'compose.yaml' \) 2>/dev/null)
  done

  # Prioriser ceux mentionnant fosrl/pangolin
  local prioritized=() others=()
  for f in "${compose_candidates[@]}"; do
    if grep -q "fosrl/pangolin" "$f" 2>/dev/null; then prioritized+=("$f"); else others+=("$f"); fi
  done
  local ordered=()
  ordered=("${prioritized[@]}" "${others[@]}")

  if [[ -z "$COMPOSE_PATH" && ${#ordered[@]} -gt 0 ]]; then
    COMPOSE_PATH=$(choose_from_list "docker-compose.yml" "${ordered[@]}")
    log "Sélection docker-compose.yml: $COMPOSE_PATH"
  fi

  # Traefik config: essayer relative à COMPOSE_PATH
  local base=""; [[ -n "$COMPOSE_PATH" ]] && base="$(dirname "$COMPOSE_PATH")"
  if [[ -z "$TRAEFIK_CONFIG_PATH" && -n "$base" ]]; then
    local rel="$base/config/traefik/traefik_config.yml"
    if [[ -f "$rel" ]]; then
      TRAEFIK_CONFIG_PATH="$rel"
      log "Traefik config détecté: $TRAEFIK_CONFIG_PATH"
    fi
  fi
  if [[ -z "$TRAEFIK_CONFIG_PATH" ]]; then
    local traefik_candidates=()
    for r in "${roots[@]}"; do
      while IFS= read -r f; do traefik_candidates+=("$f"); done < <(find "$r" -maxdepth 5 -type f -name 'traefik_config.yml' 2>/dev/null)
    done
    if [[ ${#traefik_candidates[@]} -gt 0 ]]; then
      TRAEFIK_CONFIG_PATH=$(choose_from_list "traefik_config.yml" "${traefik_candidates[@]}")
      log "Sélection traefik_config.yml: $TRAEFIK_CONFIG_PATH"
    fi
  fi

  # Config dir: essayer base/config
  if [[ -z "$CONFIG_DIR" && -n "$base" && -d "$base/config" ]]; then
    CONFIG_DIR="$base/config"
    log "Dossier config détecté: $CONFIG_DIR"
  fi
  if [[ -z "$CONFIG_DIR" ]]; then
    local config_candidates=()
    for r in "${roots[@]}"; do
      while IFS= read -r d; do config_candidates+=("$d"); done < <(find "$r" -maxdepth 4 -type d -name 'config' 2>/dev/null)
    done
    if [[ ${#config_candidates[@]} -gt 0 ]]; then
      CONFIG_DIR=$(choose_from_list "dossier config" "${config_candidates[@]}")
      log "Sélection dossier config: $CONFIG_DIR"
    fi
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

# Auto-discovery si demandé
if [[ "$AUTO_DISCOVER" == true ]]; then
  discover_paths
fi

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