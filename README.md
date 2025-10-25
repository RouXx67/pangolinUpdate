# Mise à jour de Pangolin (Docker) – Scripts CLI

Ce dépôt contient un script CLI prêt à l’emploi pour mettre à jour une instance Pangolin auto-hébergée avec Docker, sans interface graphique (adapté à Debian/Ubuntu serveur).

Script inclus:
- `update-pangolin-cli.sh`: met à jour les versions d’images dans votre `docker-compose.yml`, la version du plugin Traefik Badger dans `traefik_config.yml`, effectue une sauvegarde de la configuration, et exécute les commandes Docker nécessaires (down → pull → up -d).

Référence officielle:
- Documentation Pangolin – How to Update: https://docs.pangolin.net/self-host/how-to-update

## Prérequis
- Docker installé et en fonctionnement
- Docker Compose v2 (`docker compose`) ou v1 (`docker-compose`)
- Accès aux fichiers: `docker-compose.yml`, `traefik_config.yml`, et le dossier de configuration de Pangolin
- Droits suffisants pour arrêter/démarrer les services Docker

## Installation
1. Copier le script sur votre serveur (ex: `/opt/pangolin/update-pangolin-cli.sh`).
2. Rendre le script exécutable:
   ```bash
   chmod +x /opt/pangolin/update-pangolin-cli.sh
   ```

## Utilisation
Exemple de commande complète:
```bash
/opt/pangolin/update-pangolin-cli.sh \
  --compose /opt/pangolin/docker-compose.yml \
  --traefik-config /opt/pangolin/config/traefik/traefik_config.yml \
  --config-dir /opt/pangolin/config \
  --backup-root /opt/backups \
  --pangolin-version 1.7.3 \
  --gerbil-version 1.2.1 \
  --traefik-version v3.4.0 \
  --badger-version v1.2.0
```
Si vous omettez des options, le script vous les demandera en ligne de commande (utilisez `-y`/`--assume-yes` pour éviter les questions et utiliser uniquement les valeurs fournies).

### Options disponibles
- `--compose PATH`             Chemin vers `docker-compose.yml`
- `--traefik-config PATH`      Chemin vers `traefik_config.yml`
- `--config-dir PATH`          Dossier de configuration à sauvegarder
- `--backup-root PATH`         Dossier de destination pour la sauvegarde
- `--pangolin-version VER`     Version d’image Pangolin (ex: `1.7.3`)
- `--gerbil-version VER`       Version d’image Gerbil (ex: `1.2.1`)
- `--traefik-version VER`      Version d’image Traefik (ex: `v3.4.0`)
- `--badger-version VER`       Version du plugin Badger (ex: `v1.2.0`)
- `--down` / `--no-down`       Exécuter (ou non) `docker compose down` (défaut: `--down`)
- `--pull` / `--no-pull`       Exécuter (ou non) `docker compose pull` (défaut: `--pull`)
- `--up` / `--no-up`           Exécuter (ou non) `docker compose up -d` (défaut: `--up`)
- `-y`, `--assume-yes`         Ne pas poser de questions; utiliser les valeurs fournies
- `-h`, `--help`               Afficher l’aide

## Journal
Le script écrit un journal détaillé dans un fichier temporaire (créé via `mktemp`), et affiche son chemin à la fin de l’exécution.

## Bonnes pratiques
- Sauvegardez toujours votre dossier de configuration avant la mise à jour.
- Mettez à jour de manière incrémentale entre versions majeures (ex: `1.0.0 → 1.1.0 → 1.2.0`).
- Après le redémarrage, vérifiez le dashboard Pangolin, l’accessibilité des sites et les tunnels (si vous utilisez Gerbil).

Pour plus d’informations et recommandations détaillées, consultez la documentation officielle: https://docs.pangolin.net/self-host/how-to-update

## Dépannage
- `docker compose` introuvable: installez Docker Compose v2 ou utilisez `docker-compose` v1.
- Droits insuffisants: exécutez le script avec un utilisateur ayant accès à Docker.
- Chemins invalides: assurez-vous que `docker-compose.yml`, `traefik_config.yml` et le dossier de configuration existent et sont accessibles.

## Licence
Ce script est fourni « tel quel ». Adaptez-le selon votre environnement et vos besoins.