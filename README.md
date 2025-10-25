# Mise à jour de Pangolin (Docker) – Scripts CLI

Ce dépôt contient un script CLI prêt à l'emploi pour mettre à jour une instance Pangolin auto-hébergée avec Docker, sans interface graphique (adapté à Debian/Ubuntu serveur).

Script inclus:
- `update-pangolin-cli.sh`: met à jour les versions d'images dans votre `docker-compose.yml`, la version du plugin Traefik Badger dans `traefik_config.yml`, effectue une sauvegarde de la configuration, et exécute les commandes Docker nécessaires (down → pull → up -d).

Référence officielle:
- Documentation Pangolin – How to Update: https://docs.pangolin.net/self-host/how-to-update

## Prérequis
- Docker installé et en fonctionnement
- Docker Compose v2 (`docker compose`) ou v1 (`docker-compose`)
- Accès aux fichiers: `docker-compose.yml`, et le dossier de configuration de Pangolin (le fichier `traefik_config.yml` est nécessaire uniquement si vous mettez à jour Badger)
- Droits suffisants pour arrêter/démarrer les services Docker

## Installation

Option A — Installation rapide avec wget:
```bash
wget -O /opt/pangolin/update-pangolin-cli.sh https://raw.githubusercontent.com/RouXx67/pangolinUpdate/main/update-pangolin-cli.sh
chmod +x /opt/pangolin/update-pangolin-cli.sh
```

Option B — Copie manuelle:
1. Copier le script sur votre serveur (ex: `/opt/pangolin/update-pangolin-cli.sh`).
2. Rendre le script exécutable:
   ```bash
   chmod +x /opt/pangolin/update-pangolin-cli.sh
   ```

Option C — Installation automatique via le script:
- Télécharger temporairement le script et lancer l'auto-installation dans le dossier par défaut (`/opt/pangolin`):
  ```bash
  sudo wget -O /tmp/update-pangolin-cli.sh https://raw.githubusercontent.com/RouXx67/pangolinUpdate/main/update-pangolin-cli.sh \
    && sudo bash /tmp/update-pangolin-cli.sh --self-install
  ```
- Installer dans un dossier personnalisé (ex: `/srv/pangolin`):
  ```bash
  sudo wget -O /tmp/update-pangolin-cli.sh https://raw.githubusercontent.com/RouXx67/pangolinUpdate/main/update-pangolin-cli.sh \
    && sudo bash /tmp/update-pangolin-cli.sh --self-install --install-path /srv/pangolin
  ```
- Alternative avec curl:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/RouXx67/pangolinUpdate/main/update-pangolin-cli.sh -o /tmp/update-pangolin-cli.sh \
    && sudo bash /tmp/update-pangolin-cli.sh --self-install
  ```

Une fois installé, lancez le script depuis son emplacement:
```bash
sudo /opt/pangolin/update-pangolin-cli.sh --auto-discover --backup-root /srv/backups
```

## Utilisation

### Auto-découverte (recommandé)
Le script peut automatiquement rechercher vos fichiers Pangolin sur le système :

```bash
# Auto-découverte complète (sans mise à jour Badger)
./update-pangolin-cli.sh --auto-discover --backup-root /srv/backups \
  --pangolin-version 1.7.3 --gerbil-version 1.2.1 --traefik-version v3.4.0

# Auto-découverte dans un dossier spécifique
./update-pangolin-cli.sh --auto-discover --search-root /srv/pangolin --backup-root /srv/backups

# Mode non-interactif (prend automatiquement le premier résultat trouvé)
./update-pangolin-cli.sh --auto-discover -y --backup-root /srv/backups \
  --pangolin-version 1.7.3 --gerbil-version 1.2.1 --traefik-version v3.4.0
```

#### Scénarios d’utilisation: avec ou sans mise à jour Badger
- Sans mise à jour Badger (traefik_config.yml optionnel, ignoré si absent):
```bash
./update-pangolin-cli.sh --auto-discover --backup-root /srv/backups \
  --pangolin-version 1.7.3 --gerbil-version 1.2.1 --traefik-version v3.4.0
```
- Avec mise à jour Badger (nécessite le chemin vers traefik_config.yml):
```bash
./update-pangolin-cli.sh --auto-discover --backup-root /srv/backups \
  --pangolin-version 1.7.3 --gerbil-version 1.2.1 --traefik-version v3.4.0 \
  --badger-version v1.2.0 --traefik-config /srv/pangolin/config/traefik/traefik_config.yml
```

### Configuration manuelle
Exemple de commande complète avec chemins spécifiés manuellement :
```bash
./update-pangolin-cli.sh \
  --compose /srv/pangolin/docker-compose.yml \
  --traefik-config /srv/pangolin/config/traefik/traefik_config.yml \
  --config-dir /srv/pangolin/config \
  --backup-root /srv/backups \
  --pangolin-version 1.7.3 \
  --gerbil-version 1.2.1 \
  --traefik-version v3.4.0 \
  --badger-version v1.2.0
```

Si vous omettez des options, le script vous les demandera en ligne de commande (utilisez `-y`/`--assume-yes` pour éviter les questions et utiliser uniquement les valeurs fournies).

### Options disponibles
- `--compose PATH`             Chemin vers `docker-compose.yml`
- `--traefik-config PATH`      Chemin vers `traefik_config.yml` (optionnel; requis uniquement avec `--badger-version`)
- `--config-dir PATH`          Dossier de configuration à sauvegarder
- `--backup-root PATH`         Dossier de destination pour la sauvegarde
- `--pangolin-version VER`     Version d'image Pangolin (ex: `1.7.3`)
- `--gerbil-version VER`       Version d'image Gerbil (ex: `1.2.1`)
- `--traefik-version VER`      Version d'image Traefik (ex: `v3.4.0`)
- `--badger-version VER`       Version du plugin Badger (ex: `v1.2.0`)
- `--auto-discover`            Rechercher automatiquement les fichiers Pangolin
- `--search-root PATH`         Racine de recherche pour `--auto-discover` (par défaut: `/srv`, `/opt`, `/var`, `/etc`, `/home/*`, `/root`)
- `--self-install`             Installer automatiquement le script dans le dossier cible
- `--install-path PATH`        Dossier cible pour `--self-install` (défaut: `/opt/pangolin`)
- `--down` / `--no-down`       Exécuter (ou non) `docker compose down` (défaut: `--down`)
- `--pull` / `--no-pull`       Exécuter (ou non) `docker compose pull` (défaut: `--pull`)
- `--up` / `--no-up`           Exécuter (ou non) `docker compose up -d` (défaut: `--up`)
- `-y`, `--assume-yes`         Ne pas poser de questions; utiliser les valeurs fournies
- `-h`, `--help`               Afficher l'aide

### Comment fonctionne l'auto-découverte
Le script recherche automatiquement :
1. **docker-compose.yml** : dans `/srv`, `/opt`, `/var`, `/etc`, `/home/*`, `/root` (jusqu'à 5 niveaux de profondeur)
   - Priorise les fichiers contenant `fosrl/pangolin`
2. **traefik_config.yml** : d'abord relativement au docker-compose trouvé (`base/config/traefik/traefik_config.yml`), puis recherche globale (utilisé uniquement si vous fournissez `--badger-version`)
3. **Dossier config** : d'abord relativement au docker-compose trouvé (`base/config`), puis recherche globale

Si plusieurs candidats sont trouvés, le script propose une sélection interactive (sauf avec `--assume-yes` qui prend automatiquement le premier).

## Journal
Le script écrit un journal détaillé dans un fichier temporaire (créé via `mktemp`), et affiche son chemin à la fin de l'exécution.

## Bonnes pratiques
- Sauvegardez toujours votre dossier de configuration avant la mise à jour.
- Mettez à jour de manière incrémentale entre versions majeures (ex: `1.0.0 → 1.1.0 → 1.2.0`).
- Après le redémarrage, vérifiez le dashboard Pangolin, l'accessibilité des sites et les tunnels (si vous utilisez Gerbil).
- Utilisez `--auto-discover` pour éviter de spécifier manuellement les chemins si Pangolin n'est pas dans `/opt/pangolin`.

Pour plus d'informations et recommandations détaillées, consultez la documentation officielle: https://docs.pangolin.net/self-host/how-to-update

## Dépannage
- `docker compose` introuvable: installez Docker Compose v2 ou utilisez `docker-compose` v1.
- Droits insuffisants: exécutez le script avec un utilisateur ayant accès à Docker (et `sudo` pour l'installation dans un dossier protégé comme `/opt`).
- Chemins invalides: assurez-vous que `docker-compose.yml` et le dossier de configuration existent; `traefik_config.yml` n'est requis que si vous mettez à jour Badger.
- Mise à jour Badger ignorée: si `--badger-version` est fourni mais `traefik_config.yml` est introuvable, le script journalise l'ignorance et poursuit les autres opérations.
- Auto-découverte ne trouve rien: utilisez `--search-root` pour spécifier le dossier racine où chercher, ou spécifiez les chemins manuellement.

## Licence
Ce script est fourni « tel quel ». Adaptez-le selon votre environnement et vos besoins.