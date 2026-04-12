#!/usr/bin/env bash
set -euo pipefail

# Script CLI de mise à jour Pangolin (Linux, sans interface graphique)
# Prérequis: docker, docker compose (ou docker-compose), curl

# ============================================================
# COULEURS (doit être en premier)
# ============================================================
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; RESET=''
fi

# ============================================================
# UTILISATION
# ============================================================
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
  --auto-discover            Découvrir automatiquement les chemins [activé par défaut]
  --search-root PATH         Racine de recherche pour --auto-discover
  --self-install             Installer ce script dans /opt/pangolin (ou --install-path)
  --install-path PATH        Dossier cible pour --self-install (défaut: /opt/pangolin)
  -y, --assume-yes           Ne pas poser de questions, utiliser les valeurs par défaut
  -h, --help                 Afficher cette aide

Exemples:
  ./update-pangolin-cli.sh \
    --compose /srv/pangolin/docker-compose.yml \
    --traefik-config /srv/pangolin/config/traefik/traefik_config.yml \
    --config-dir /srv/pangolin/config \
    --backup-root /srv/backups \
    --pangolin-version 1.7.3 --gerbil-version 1.2.1 \
    --traefik-version v3.4.0 --badger-version v1.2.0

  ./update-pangolin-cli.sh --auto-discover --backup-root /srv/backups

  ./update-pangolin-cli.sh --self-install --install-path /srv/pangolin
EOF
}

# ============================================================
# DÉPENDANCES
# ============================================================
need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo -e "${RED}Commande requise introuvable: $1${RESET}" >&2
    exit 1
  fi
}

need_cmd docker
need_cmd curl

# Détecter docker compose
DOCKER_COMPOSE_BIN=""
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE_BIN="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE_BIN="docker-compose"
else
  echo -e "${RED}docker compose / docker-compose introuvable.${RESET}" >&2
  exit 1
fi

# ============================================================
# VALEURS PAR DÉFAUT
# ============================================================
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
AUTO_DISCOVER=true
SEARCH_ROOT=""
SELF_INSTALL=false
INSTALL_PATH="/opt/pangolin"

# ============================================================
# PARSE ARGUMENTS
# ============================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose)           COMPOSE_PATH="$2";        shift 2;;
    --traefik-config)    TRAEFIK_CONFIG_PATH="$2"; shift 2;;
    --config-dir)        CONFIG_DIR="$2";          shift 2;;
    --backup-root)       BACKUP_ROOT="$2";         shift 2;;
    --pangolin-version)  PANGOLIN_VER="$2";        shift 2;;
    --gerbil-version)    GERBIL_VER="$2";          shift 2;;
    --traefik-version)   TRAEFIK_VER="$2";         shift 2;;
    --badger-version)    BADGER_VER="$2";          shift 2;;
    --down)              DO_DOWN=true;             shift;;
    --no-down)           DO_DOWN=false;            shift;;
    --pull)              DO_PULL=true;             shift;;
    --no-pull)           DO_PULL=false;            shift;;
    --up)                DO_UP=true;              shift;;
    --no-up)             DO_UP=false;             shift;;
    --auto-discover)     AUTO_DISCOVER=true;       shift;;
    --search-root)       SEARCH_ROOT="$2";         shift 2;;
    --self-install)      SELF_INSTALL=true;        shift;;
    --install-path)      INSTALL_PATH="$2";        shift 2;;
    -y|--assume-yes)     ASSUME_YES=true;          shift;;
    -h|--help)           usage; exit 0;;
    *) echo -e "${RED}Option inconnue: $1${RESET}" >&2; usage; exit 1;;
  esac
done

# ============================================================
# LOGGING
# ============================================================
stamp() { date '+%Y-%m-%d %H:%M:%S'; }
log()     { echo -e "$(stamp) ${GREEN}[INFO]${RESET}  $*"; }
warn()    { echo -e "$(stamp) ${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "$(stamp) ${RED}[ERROR]${RESET} $*" >&2; }
section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════${RESET}"; \
            echo -e "${BOLD}${BLUE}  $*${RESET}"; \
            echo -e "${BOLD}${BLUE}══════════════════════════════${RESET}\n"; }

LOGFILE="/tmp/pangolin_update_$(date '+%Y%m%d_%H%M%S').log"
exec > >(tee -a "$LOGFILE") 2>&1

log "Journal: $LOGFILE"

# ============================================================
# FONCTIONS UTILITAIRES
# ============================================================
prompt_if_empty() {
  local varname="$1"
  local prompt="$2"
  local current_value
  current_value="$(eval echo "\${${varname}:-}")"
  if [[ -z "$current_value" && "$ASSUME_YES" != true ]]; then
    read -r -p "$prompt" current_value < /dev/tty
    eval "${varname}=\"${current_value}\""
  fi
}

prompt_with_default() {
  local varname="$1"
  local prompt="$2"
  local def="$3"
  local current_value
  current_value="$(eval echo "\${${varname}:-}")"
  if [[ -z "$current_value" ]]; then
    if [[ "$ASSUME_YES" == true ]]; then
      eval "${varname}=\"${def}\""
    else
      local input
      echo -ne "${CYAN}${prompt}${RESET} [${BOLD}${def}${RESET}]: " > /dev/tty
      read -r input < /dev/tty
      if [[ -z "$input" ]]; then input="$def"; fi
      eval "${varname}=\"${input}\""
    fi
  fi
}

require_path() {
  local p="$1"
  local desc="$2"
  if [[ -z "$p" ]]; then
    error "$desc non fourni."
    exit 1
  fi
}

choose_from_list() {
  local name="$1"; shift
  local items=("$@")
  if [[ ${#items[@]} -eq 0 ]]; then echo ""; return 0; fi
  if [[ ${#items[@]} -eq 1 ]]; then echo "${items[0]}"; return 0; fi
  if [[ "$ASSUME_YES" == true ]]; then echo "${items[0]}"; return 0; fi
  echo -e "${CYAN}Plusieurs candidats pour $name :${RESET}" > /dev/tty
  local i=1
  for it in "${items[@]}"; do
    echo "  [$i] $it" > /dev/tty
    ((i++))
  done
  printf "Choisissez [1-%d] (défaut 1): " "${#items[@]}" > /dev/tty
  local sel
  read -r sel < /dev/tty
  if [[ -z "$sel" ]]; then sel=1; fi
  if ! [[ "$sel" =~ ^[0-9]+$ ]] || [[ "$sel" -lt 1 ]] || [[ "$sel" -gt ${#items[@]} ]]; then sel=1; fi
  echo "${items[$((sel-1))]}"
}

# ============================================================
# RÉCUPÉRATION DES VERSIONS (Docker Hub API)
# ============================================================
latest_tag_from_hub() {
  local repo="$1"
  local pattern="$2"
  local url="https://hub.docker.com/v2/repositories/${repo}/tags?page_size=100"
  local json tag
  json=$(curl -fsSL --connect-timeout 10 "$url" 2>/dev/null || true)
  tag=$(echo "$json" \
    | grep -o '"name":"[^"]*"' \
    | sed 's/"name":"//;s/"//' \
    | grep -E "$pattern" \
    | grep -Ev '(rc|beta|alpha|latest)' \
    | sort -V -r \
    | head -n 1)
  if [[ -z "$tag" ]]; then echo "latest"; else echo "$tag"; fi
}

get_latest_pangolin() { latest_tag_from_hub "fosrl/pangolin"  '^[0-9]+\.[0-9]+\.[0-9]+$'; }
get_latest_gerbil()   { latest_tag_from_hub "fosrl/gerbil"    '^[0-9]+\.[0-9]+\.[0-9]+$'; }
get_latest_traefik()  { latest_tag_from_hub "library/traefik" '^v[0-9]+\.[0-9]+\.[0-9]+$'; }

# ============================================================
# AUTO-DISCOVERY
# ============================================================
discover_paths() {
  section "Auto-discovery"
  local roots=()
  if [[ -n "$SEARCH_ROOT" && -d "$SEARCH_ROOT" ]]; then
    roots+=("$SEARCH_ROOT")
  else
    for d in /srv /opt /var /etc; do [[ -d "$d" ]] && roots+=("$d"); done
    for h in /home/*; do [[ -d "$h" ]] && roots+=("$h"); done
    [[ -d "/root" ]] && roots+=("/root")
  fi

  # Chercher docker-compose
  local compose_candidates=()
  for r in "${roots[@]}"; do
    while IFS= read -r f; do
      compose_candidates+=("$f")
    done < <(find "$r" -maxdepth 5 -type f \
      \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \
         -o -name 'compose.yml'     -o -name 'compose.yaml' \) \
      2>/dev/null)
  done

  # Prioriser ceux contenant fosrl/pangolin
  local prioritized=() others=()
  for f in "${compose_candidates[@]}"; do
    if grep -q "fosrl/pangolin" "$f" 2>/dev/null; then
      prioritized+=("$f")
    else
      others+=("$f")
    fi
  done
  local ordered=("${prioritized[@]}" "${others[@]}")

  if [[ -z "$COMPOSE_PATH" && ${#ordered[@]} -gt 0 ]]; then
    COMPOSE_PATH=$(choose_from_list "docker-compose.yml" "${ordered[@]}")
    log "docker-compose.yml sélectionné: $COMPOSE_PATH"
  fi

  # Déduire base dir
  local base=""
  [[ -n "$COMPOSE_PATH" ]] && base="$(dirname "$COMPOSE_PATH")"

  # Chercher traefik_config.yml
  if [[ -z "$TRAEFIK_CONFIG_PATH" && -n "$base" ]]; then
    local rel="$base/config/traefik/traefik_config.yml"
    if [[ -f "$rel" ]]; then
      TRAEFIK_CONFIG_PATH="$rel"
      log "traefik_config.yml détecté: $TRAEFIK_CONFIG_PATH"
    fi
  fi
  if [[ -z "$TRAEFIK_CONFIG_PATH" ]]; then
    local traefik_candidates=()
    for r in "${roots[@]}"; do
      while IFS= read -r f; do
        traefik_candidates+=("$f")
      done < <(find "$r" -maxdepth 5 -type f -name 'traefik_config.yml' 2>/dev/null)
    done
    if [[ ${#traefik_candidates[@]} -gt 0 ]]; then
      TRAEFIK_CONFIG_PATH=$(choose_from_list "traefik_config.yml" "${traefik_candidates[@]}")
      log "traefik_config.yml sélectionné: $TRAEFIK_CONFIG_PATH"
    fi
  fi

  # Chercher dossier config
  if [[ -z "$CONFIG_DIR" && -n "$base" && -d "$base/config" ]]; then
    CONFIG_DIR="$base/config"
    log "Dossier config détecté: $CONFIG_DIR"
  fi
  if [[ -z "$CONFIG_DIR" ]]; then
    local config_candidates=()
    for r in "${roots[@]}"; do
      while IFS= read -r d; do
        config_candidates+=("$d")
      done < <(find "$r" -maxdepth 4 -type d -name 'config' 2>/dev/null)
    done
    if [[ ${#config_candidates[@]} -gt 0 ]]; then
      CONFIG_DIR=$(choose_from_list "dossier config" "${config_candidates[@]}")
      log "Dossier config sélectionné: $CONFIG_DIR"
    fi
  fi
}

# ============================================================
# BACKUP
# ============================================================
backup_config() {
  local src="$1"
  local dst_root="$2"
  mkdir -p "$dst_root"
  local ts dest
  ts="$(date '+%Y%m%d_%H%M%S')"
  dest="${dst_root%/}/config_backup_${ts}"
  log "Sauvegarde: $src → $dest"
  cp -a "$src" "$dest"

  # Rotation: garder les 5 dernières sauvegardes
  local old_backups
  mapfile -t old_backups < <(find "$dst_root" -maxdepth 1 -type d -name 'config_backup_*' | sort | head -n -5)
  for old in "${old_backups[@]}"; do
    warn "Suppression ancienne sauvegarde: $old"
    rm -rf "$old"
  done

  log "Sauvegarde terminée: $dest"
}

# ============================================================
# MISE À JOUR DES FICHIERS
# ============================================================
update_compose_file() {
  local path="$1" pang="$2" gerb="$3" traef="$4"
  # Backup avant modif
  cp "$path" "${path}.bak"
  log "Backup compose: ${path}.bak"
  sed -E -i \
    "s|(^[[:space:]]*image:[[:space:]]*)fosrl/pangolin:[^[:space:]]+|\1fosrl/pangolin:${pang}|" \
    "$path"
  sed -E -i \
    "s|(^[[:space:]]*image:[[:space:]]*)fosrl/gerbil:[^[:space:]]+|\1fosrl/gerbil:${gerb}|" \
    "$path"
  sed -E -i \
    "s|(^[[:space:]]*image:[[:space:]]*)traefik:[^[:space:]]+|\1traefik:${traef}|" \
    "$path"
  log "docker-compose.yml mis à jour."
}

update_badger_version() {
  local path="$1" badger="$2"
  cp "$path" "${path}.bak"
  log "Backup traefik_config: ${path}.bak"
  local tmp
  tmp="$(mktemp)"
  awk -v badger="${badger}" '
  BEGIN { in_badger=0 }
  {
    if ($0 ~ /^[[:space:]]*badger:[[:space:]]*$/) { in_badger=1; print; next }
    if (in_badger==1 && $0 ~ /^[[:space:]]*version:[[:space:]]*/) {
      match($0, /^[[:space:]]*/)
      print substr($0,1,RLENGTH) "version: " badger
      in_badger=2
      next
    }
    if (in_badger==1 && $0 !~ /^[[:space:]]*(version:|$)/) { in_badger=0 }
    print
  }' "$path" > "$tmp"
  mv "$tmp" "$path"
  log "traefik_config.yml mis à jour (Badger: $badger)."
}

# ============================================================
# COMPOSE RUN
# ============================================================
compose_run() {
  local file="$1"; shift
  local dir
  dir="$(dirname "$file")"
  (cd "$dir" && ${DOCKER_COMPOSE_BIN} -f "$(basename "$file")" "$@")
}

# ============================================================
# SELF-INSTALL
# ============================================================
self_install() {
  local dst="${INSTALL_PATH%/}/update-pangolin-cli.sh"
  log "Installation du script vers: $dst"
  mkdir -p "$INSTALL_PATH" || { error "Impossible de créer $INSTALL_PATH (sudo ?)"; exit 1; }
  cp "$0" "$dst"           || { error "Impossible de copier vers $dst (sudo ?)"; exit 1; }
  chmod +x "$dst"
  log "Script installé: $dst"
  log "Utilisation: $dst --help"
}

# ============================================================
# MAIN
# ============================================================

# Auto-installation
if [[ "$SELF_INSTALL" == true ]]; then
  self_install
  exit 0
fi

# Auto-discovery
if [[ "$AUTO_DISCOVER" == true ]]; then
  discover_paths
fi

section "Configuration"

# Demander les valeurs manquantes
prompt_if_empty COMPOSE_PATH "Chemin docker-compose.yml: "
if [[ -n "$BADGER_VER" ]]; then
  prompt_if_empty TRAEFIK_CONFIG_PATH "Chemin traefik_config.yml (pour Badger): "
fi
prompt_if_empty CONFIG_DIR "Dossier de configuration à sauvegarder: "

# Récupérer les dernières versions depuis Docker Hub
log "Récupération des dernières versions disponibles..."
DEFAULT_PANGOLIN_VER="$(get_latest_pangolin)"
DEFAULT_GERBIL_VER="$(get_latest_gerbil)"
DEFAULT_TRAEFIK_VER="$(get_latest_traefik)"
log "  Pangolin : $DEFAULT_PANGOLIN_VER"
log "  Gerbil   : $DEFAULT_GERBIL_VER"
log "  Traefik  : $DEFAULT_TRAEFIK_VER"

prompt_with_default PANGOLIN_VER "Version Pangolin" "$DEFAULT_PANGOLIN_VER"
prompt_with_default GERBIL_VER   "Version Gerbil"   "$DEFAULT_GERBIL_VER"
prompt_with_default TRAEFIK_VER  "Version Traefik"  "$DEFAULT_TRAEFIK_VER"

# Validation
require_path "$COMPOSE_PATH" "docker-compose.yml"
require_path "$CONFIG_DIR"   "Dossier de configuration"

# BACKUP_ROOT = dossier du docker-compose si non fourni
if [[ -z "$BACKUP_ROOT" ]]; then
  BACKUP_ROOT="$(dirname "$COMPOSE_PATH")"
fi

# ============================================================
# RÉSUMÉ + CONFIRMATION
# ============================================================
section "Résumé"
echo -e "  docker-compose.yml : ${BOLD}$COMPOSE_PATH${RESET}"
echo -e "  Config dir         : ${BOLD}$CONFIG_DIR${RESET}"
echo -e "  Backup root        : ${BOLD}$BACKUP_ROOT${RESET}"
[[ -n "$TRAEFIK_CONFIG_PATH" ]] && \
echo -e "  traefik_config.yml : ${BOLD}$TRAEFIK_CONFIG_PATH${RESET}"
echo ""
echo -e "  Pangolin → ${CYAN}$PANGOLIN_VER${RESET}"
echo -e "  Gerbil   → ${CYAN}$GERBIL_VER${RESET}"
echo -e "  Traefik  → ${CYAN}$TRAEFIK_VER${RESET}"
[[ -n "$BADGER_VER" ]] && \
echo -e "  Badger   → ${CYAN}$BADGER_VER${RESET}"
echo ""
echo -e "  compose down : ${BOLD}$DO_DOWN${RESET} | pull : ${BOLD}$DO_PULL${RESET} | up : ${BOLD}$DO_UP${RESET}"
echo ""

if [[ "$ASSUME_YES" != true ]]; then
  read -r -p "Continuer ? [O/n]: " confirm < /dev/tty
  confirm="${confirm:-O}"
  if [[ ! "$confirm" =~ ^[OoYy]$ ]]; then
    log "Annulé par l'utilisateur."
    exit 0
  fi
fi

# ============================================================
# EXÉCUTION
# ============================================================
section "Exécution"

log "1/5 - Sauvegarde de la configuration..."
backup_config "$CONFIG_DIR" "$BACKUP_ROOT"

log "2/5 - Mise à jour de docker-compose.yml..."
update_compose_file "$COMPOSE_PATH" "$PANGOLIN_VER" "$GERBIL_VER" "$TRAEFIK_VER"

log "3/5 - Mise à jour de Badger..."
if [[ -n "$BADGER_VER" && -n "$TRAEFIK_CONFIG_PATH" && -f "$TRAEFIK_CONFIG_PATH" ]]; then
  update_badger_version "$TRAEFIK_CONFIG_PATH" "$BADGER_VER"
else
  warn "Badger ignoré (traefik_config.yml absent ou --badger-version non spécifié)."
fi

log "4/5 - Redémarrage du stack..."
if [[ "$DO_DOWN" == true ]]; then
  log "  → compose down"
  compose_run "$COMPOSE_PATH" down || true
fi
if [[ "$DO_PULL" == true ]]; then
  log "  → compose pull"
  compose_run "$COMPOSE_PATH" pull
fi
if [[ "$DO_UP" == true ]]; then
  log "  → compose up -d"
  compose_run "$COMPOSE_PATH" up -d
fi

log "5/5 - Vérification post-démarrage..."
sleep 5
running=$(compose_run "$COMPOSE_PATH" ps 2>/dev/null | grep -c 'running\|Up' || echo "0")
log "  → Conteneurs actifs: $running"

section "Terminé"
log "Journal complet: $LOGFILE"
log "Vérifiez le dashboard Pangolin et l'accessibilité de vos sites."

exit 0
