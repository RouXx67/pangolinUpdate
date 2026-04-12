#!/usr/bin/env bash
set -euo pipefail

# Script CLI de mise à jour Pangolin (Linux, sans interface graphique)
# Prérequis: docker, docker compose (ou docker-compose), curl

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
  --pangolin-version VER     Version d'image Pangolin (ex: 1.17.0)
  --gerbil-version VER       Version d'image Gerbil (ex: 1.4.0)
  --traefik-version VER      Version d'image Traefik (ex: v3.4.0)
  --badger-version VER       Version du plugin Badger (ex: v1.2.0)
  --down/--no-down           Exécuter (ou non) docker compose down (défaut: --down)
  --pull/--no-pull           Exécuter (ou non) docker compose pull (défaut: --pull)
  --up/--no-up               Exécuter (ou non) docker compose up -d (défaut: --up)
  --auto-discover            Découvrir automatiquement les chemins [activé par défaut]
  --search-root PATH         Racine de recherche pour --auto-discover
  --self-install             Installer ce script dans /opt/pangolin (ou --install-path)
  --install-path PATH        Dossier cible pour --self-install (défaut: /opt/pangolin)
  --check-only               Afficher les dernières versions disponibles et quitter
  -y, --assume-yes           Ne pas poser de questions, utiliser les valeurs par défaut
  -h, --help                 Afficher cette aide

Exemples:
  ./update-pangolin-cli.sh \
    --compose /srv/pangolin/docker-compose.yml \
    --traefik-config /srv/pangolin/config/traefik/traefik_config.yml \
    --config-dir /srv/pangolin/config \
    --backup-root /srv/backups \
    --pangolin-version 1.17.0 --gerbil-version 1.4.0 --traefik-version v3.4.0

  ./update-pangolin-cli.sh --auto-discover --backup-root /srv/backups

  ./update-pangolin-cli.sh --check-only

  ./update-pangolin-cli.sh --self-install --install-path /srv/pangolin
EOF
}

# ============================================================
# COULEURS
# ============================================================
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; RESET=''
fi

# ============================================================
# DÉPENDANCES
# ============================================================
need_cmd() {
  if ! command -v " $ 1" >/dev/null 2>&1; then
    echo -e " $ {RED}Commande requise introuvable:  $ 1 $ {RESET}" >&2
    exit 1
  fi
}

need_cmd docker
need_cmd curl

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
# DEFAULTS
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
CHECK_ONLY=false

# ============================================================
# PARSE ARGUMENTS
# ============================================================
while [[  $ # -gt 0 ]]; do
  case " $ 1" in
    --compose)           COMPOSE_PATH=" $ 2";        shift 2;;
    --traefik-config)    TRAEFIK_CONFIG_PATH=" $ 2"; shift 2;;
    --config-dir)        CONFIG_DIR=" $ 2";          shift 2;;
    --backup-root)       BACKUP_ROOT=" $ 2";         shift 2;;
    --pangolin-version)  PANGOLIN_VER=" $ 2";        shift 2;;
    --gerbil-version)    GERBIL_VER=" $ 2";          shift 2;;
    --traefik-version)   TRAEFIK_VER=" $ 2";         shift 2;;
    --badger-version)    BADGER_VER=" $ 2";          shift 2;;
    --down)              DO_DOWN=true;             shift;;
    --no-down)           DO_DOWN=false;            shift;;
    --pull)              DO_PULL=true;             shift;;
    --no-pull)           DO_PULL=false;            shift;;
    --up)                DO_UP=true;               shift;;
    --no-up)             DO_UP=false;              shift;;
    --auto-discover)     AUTO_DISCOVER=true;       shift;;
    --search-root)       SEARCH_ROOT=" $ 2";         shift 2;;
    --self-install)      SELF_INSTALL=true;        shift;;
    --install-path)      INSTALL_PATH=" $ 2";
