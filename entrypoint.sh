#!/bin/bash
set -e # Quitte immédiatement si une commande échoue.

VENV_DIR="/root/venv"

# Vérifie si le sous-répertoire 'bin' de l'environnement virtuel existe déjà.
# C'est un indicateur plus fiable que de simplement vérifier l'existence de VENV_DIR.
if [ ! -d "$VENV_DIR/bin" ]; then
    echo "===> Création de l'environnement virtuel Python à $VENV_DIR..."
    virtualenv "$VENV_DIR"
else
    echo "===> Environnement virtuel Python existant à $VENV_DIR."
fi

echo "===> Activation de l'environnement virtuel Python..."
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

echo "===> Exécution de la commande CMD: $@"
# Exécute la commande passée en argument (provenant de CMD dans le Dockerfile)
exec "$@"
