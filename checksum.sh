# CHKSUM: e4f0c7f81a044a40e025325a20cd8ebb7aae6953a478a7789a0bfa43dd8b5ec4
#!/bin/bash

# MODE OPÉRATOIRE :
#
# Ce script a trois modes de fonctionnement pour gérer une somme de contrôle (checksum)
# en première ligne d'un fichier, sous la forme "# CHKSUM: <valeur_sha256>".
# Il peut générer, vérifier ou mettre à jour cette somme de contrôle.
#
# 1. Génération et Insertion (`generate` ou `--generate`):
#    - Si une ligne "# CHKSUM: ..." existe en première ligne du fichier, elle est d'abord retirée.
#    - Calcule la somme de contrôle SHA256 du contenu restant (ou du fichier entier si aucune ligne CHKSUM n'était présente).
#    - Insère une nouvelle première ligne dans le fichier avec le format
#      "# CHKSUM: <somme_de_contrôle_calculée_du_contenu>".
#    - Ce mode écrase toujours la ligne de checksum existante si présente.
#
# 2. Vérification (`verify` ou `--verify`):
#    - Lit la première ligne du fichier pour y trouver une somme de contrôle stockée ("# CHKSUM: <valeur_stockee>").
#    - Si trouvée, supprime temporairement cette première ligne pour obtenir le contenu original.
#    - Calcule la somme de contrôle SHA256 de ce contenu original.
#    - Compare la somme de contrôle calculée avec <valeur_stockee>.
#    - Indique si les sommes de contrôle correspondent ou non et quitte avec un code de succès (0) ou d'échec (1).
#
# 3. Mise à jour (`update` ou `--update`):
#    - Calcule la somme de contrôle SHA256 du contenu du fichier (en ignorant une éventuelle ligne CHKSUM existante).
#    - Si une ligne CHKSUM existe en première ligne et que sa valeur correspond à la somme calculée, le fichier n'est pas modifié.
#    - Sinon (pas de ligne CHKSUM, ou valeur incorrecte), la première ligne est insérée/mise à jour avec la somme de contrôle correcte.
#
# USAGE:
#   ./ajouter_checksum_referentiel.sh <fichier> generate|verify|update
#
# EXEMPLES:
#   ./ajouter_checksum_referentiel.sh mon_fichier.txt generate
#   ./ajouter_checksum_referentiel.sh mon_fichier.txt verify
#   ./ajouter_checksum_referentiel.sh mon_fichier.txt update

set -e # Quitte immédiatement si une commande échoue
# set -u # Traite les variables non définies comme une erreur. Peut être utile pour le débogage.
# set -o pipefail # La valeur de retour d'un pipeline est celle de la dernière commande à échouer.

# --- Constantes ---
readonly CHECKSUM_LINE_MARKER="# CHKSUM: " # Préfixe de la ligne de checksum, incluant le commentaire '#' et l'espace.

# --- Constantes de couleur ---
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_RESET='\033[0m'

# --- Variables globales pour les fichiers temporaires (pour cleanup) ---
TEMP_FILE_A=""
TEMP_FILE_B=""

# Fonction de nettoyage pour supprimer les fichiers temporaires
cleanup() {
    if [ -n "$TEMP_FILE_A" ] && [ -f "$TEMP_FILE_A" ]; then
        rm -f "$TEMP_FILE_A"
    fi
    if [ -n "$TEMP_FILE_B" ] && [ -f "$TEMP_FILE_B" ]; then
        rm -f "$TEMP_FILE_B"
    fi
}
trap cleanup EXIT INT TERM # Appelle la fonction cleanup à la sortie du script (normale ou sur erreur/interruption)

# Fonction pour afficher l'usage et quitter
usage() {
    echo "Usage: $0 <fichier> <mode>"
    echo "Modes disponibles: 'generate', 'verify', 'update'"
    exit 1
}

# --- Validation des arguments ---
if [ "$#" -ne 2 ]; then
    usage
fi

TARGET_FILE="$1"
MODE="$2"

if [ ! -f "$TARGET_FILE" ]; then
    echo "Erreur: Le fichier '$TARGET_FILE' n'existe pas."
    exit 1
fi

# --- Logique principale ---

if [ "$MODE" == "generate" ] || [ "$MODE" == "--generate" ]; then
    echo "Mode: Génération et insertion de la somme de contrôle pour '$TARGET_FILE'"

    TEMP_FILE_A=$(mktemp) # Fichier temporaire pour le contenu sans l'ancienne ligne de checksum

    # Lire la première ligne du fichier cible
    FIRST_LINE_ORIGINAL=$(head -n 1 "$TARGET_FILE" 2>/dev/null || true)

    if [[ "$FIRST_LINE_ORIGINAL" == ${CHECKSUM_LINE_MARKER}* ]]; then
        echo "Ancienne ligne de checksum détectée. Elle sera ignorée pour le calcul du checksum du contenu."
        tail -n +2 "$TARGET_FILE" > "$TEMP_FILE_A"
    else
        echo "Aucune ancienne ligne de checksum détectée. Utilisation du contenu complet pour le checksum."
        cat "$TARGET_FILE" > "$TEMP_FILE_A"
    fi

    # Calculer le checksum du contenu (stocké dans TEMP_FILE_A)
    # sha256sum gère correctement un TEMP_FILE_A vide (par exemple, si le fichier original était vide ou ne contenait que la ligne de checksum)
    CONTENT_CHKSUM=$(sha256sum "$TEMP_FILE_A" | awk '{print $1}')
    echo "Somme de contrôle calculée du contenu: $CONTENT_CHKSUM"

    NEW_CHECKSUM_LINE="${CHECKSUM_LINE_MARKER}${CONTENT_CHKSUM}"

    # Créer le nouveau contenu final dans un autre fichier temporaire
    TEMP_FILE_B=$(mktemp)
    echo "$NEW_CHECKSUM_LINE" > "$TEMP_FILE_B" # Nouvelle première ligne
    cat "$TEMP_FILE_A" >> "$TEMP_FILE_B"       # Ajouter le contenu (qui était dans TEMP_FILE_A)

    # Remplacer le fichier original
    mv "$TEMP_FILE_B" "$TARGET_FILE"
    # TEMP_FILE_B est renommé, donc il ne sera plus trouvé par cleanup sous son nom temporaire.
    # TEMP_FILE_A sera nettoyé par trap.

    echo "Fichier '$TARGET_FILE' mis à jour. Nouvelle première ligne: $NEW_CHECKSUM_LINE"

elif [ "$MODE" == "verify" ] || [ "$MODE" == "--verify" ]; then
    echo "Mode: Vérification de la somme de contrôle pour '$TARGET_FILE'"

    FIRST_LINE=$(head -n 1 "$TARGET_FILE" 2>/dev/null || true)

    if [[ "$FIRST_LINE" != ${CHECKSUM_LINE_MARKER}* ]]; then
        echo -e "${COLOR_RED}Erreur${COLOR_RESET}: Aucune ligne de somme de contrôle valide (format '${CHECKSUM_LINE_MARKER}...') trouvée en première ligne de '$TARGET_FILE'."
        exit 1
    fi

    STORED_CHKSUM=$(echo "$FIRST_LINE" | sed "s/^${CHECKSUM_LINE_MARKER}//")
    echo "Somme de contrôle stockée trouvée: $STORED_CHKSUM"

    # Valider la longueur et le format du checksum extrait (SHA256 = 64 caractères hex)
    if ! [[ "$STORED_CHKSUM" =~ ^[a-f0-9]{64}$ ]]; then
        echo -e "${COLOR_RED}Erreur${COLOR_RESET}: La somme de contrôle stockée '$STORED_CHKSUM' est malformée (doit être 64 caractères hexadécimaux)."
        exit 1
    fi

    # Créer un fichier temporaire avec le contenu SANS la première ligne de checksum
    TEMP_FILE_A=$(mktemp)
    tail -n +2 "$TARGET_FILE" > "$TEMP_FILE_A"

    CALCULATED_CHKSUM=$(sha256sum "$TEMP_FILE_A" | awk '{print $1}')
    echo "Somme de contrôle calculée du contenu (sans la première ligne): $CALCULATED_CHKSUM"

    if [ "$STORED_CHKSUM" == "$CALCULATED_CHKSUM" ]; then
        echo -e "${COLOR_GREEN}SUCCÈS:${COLOR_RESET} La somme de contrôle du fichier correspond à la somme de contrôle stockée."
        exit 0 # Succès
    else
        echo -e "${COLOR_RED}ÉCHEC:${COLOR_RESET} La somme de contrôle du fichier NE CORRESPOND PAS à la somme de contrôle stockée."
        echo -e "  Attendu (stocké) : ${COLOR_RED}$STORED_CHKSUM${COLOR_RESET}"
        echo -e "  Calculé (contenu): ${COLOR_GREEN}$CALCULATED_CHKSUM${COLOR_RESET}"
        exit 1 # Échec
    fi

elif [ "$MODE" == "update" ] || [ "$MODE" == "--update" ]; then
    echo "Mode: Mise à jour de la somme de contrôle pour '$TARGET_FILE'"

    TEMP_FILE_A=$(mktemp) # Fichier temporaire pour le contenu sans l'éventuelle ligne de checksum
    HAS_EXISTING_CHECKSUM_LINE=false
    STORED_CHKSUM_VALUE=""

    # Lire la première ligne du fichier cible
    FIRST_LINE_ORIGINAL=$(head -n 1 "$TARGET_FILE" 2>/dev/null || true)

    if [[ "$FIRST_LINE_ORIGINAL" == ${CHECKSUM_LINE_MARKER}* ]]; then
        HAS_EXISTING_CHECKSUM_LINE=true
        STORED_CHKSUM_VALUE=$(echo "$FIRST_LINE_ORIGINAL" | sed "s/^${CHECKSUM_LINE_MARKER}//")
        # Valider le checksum stocké avant de continuer
        if ! [[ "$STORED_CHKSUM_VALUE" =~ ^[a-f0-9]{64}$ ]]; then
            echo "Ligne de checksum existante malformée: '$FIRST_LINE_ORIGINAL'. Elle sera remplacée."
            HAS_EXISTING_CHECKSUM_LINE=false # Traiter comme si elle n'existait pas pour forcer la regénération
            cat "$TARGET_FILE" > "$TEMP_FILE_A" # Utiliser le fichier entier car la ligne de checksum est invalide
        else
            echo "Ligne de checksum existante trouvée: $STORED_CHKSUM_VALUE"
            tail -n +2 "$TARGET_FILE" > "$TEMP_FILE_A" # Contenu sans la ligne de checksum
        fi
    else
        echo "Aucune ligne de checksum détectée en première ligne."
        cat "$TARGET_FILE" > "$TEMP_FILE_A" # Contenu complet du fichier
    fi

    # Calculer le checksum du contenu actuel (stocké dans TEMP_FILE_A)
    CURRENT_CONTENT_CHKSUM=$(sha256sum "$TEMP_FILE_A" | awk '{print $1}')
    echo "Somme de contrôle actuelle du contenu: $CURRENT_CONTENT_CHKSUM"

    if [ "$HAS_EXISTING_CHECKSUM_LINE" == true ] && [ "$STORED_CHKSUM_VALUE" == "$CURRENT_CONTENT_CHKSUM" ]; then
        echo "La somme de contrôle est déjà à jour. Aucune modification nécessaire."
        exit 0
    fi

    # Si on arrive ici, il faut générer/mettre à jour la ligne de checksum
    if [ "$HAS_EXISTING_CHECKSUM_LINE" == true ]; then
        echo "Mise à jour de la somme de contrôle (Ancienne: $STORED_CHKSUM_VALUE, Nouvelle: $CURRENT_CONTENT_CHKSUM)."
    else
        echo "Génération d'une nouvelle somme de contrôle: $CURRENT_CONTENT_CHKSUM."
    fi

    NEW_CHECKSUM_LINE="${CHECKSUM_LINE_MARKER}${CURRENT_CONTENT_CHKSUM}"

    TEMP_FILE_B=$(mktemp)
    echo "$NEW_CHECKSUM_LINE" > "$TEMP_FILE_B"
    cat "$TEMP_FILE_A" >> "$TEMP_FILE_B"

    mv "$TEMP_FILE_B" "$TARGET_FILE"
    echo "Fichier '$TARGET_FILE' mis à jour. Nouvelle première ligne: $NEW_CHECKSUM_LINE"

else
    echo -e "${COLOR_RED}Erreur${COLOR_RESET}: Mode '$MODE' inconnu."
    usage
fi

exit 0
