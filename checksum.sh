# CHKSUM: e4f0c7f81a044a40e025325a20cd8ebb7aae6953a478a7789a0bfa43dd8b5ec4
#!/bin/bash

# MODE OPÉRATOIRE :
#
# Ce script a trois modes de fonctionnement pour gérer une somme de contrôle (checksum)
# en première ligne d'un fichier, sous la forme "# CHKSUM: <valeur_sha256>".
# Il peut générer, vérifier ou mettre à jour cette somme de contrôle.
#
# 1. Génération et Insertion (`generate` ou `--generate`):
#    - Détermine la position attendue de la ligne CHKSUM (ligne 2 si la ligne 1 est un shebang, sinon ligne 1).
#    - Supprime temporairement toute ligne CHKSUM existante à cette position.
#    - Calcule la somme de contrôle SHA256 du contenu restant (après suppression de l'éventuelle ligne CHKSUM et de la shebang si présente en ligne 1).
#    - Insère une nouvelle ligne CHKSUM avec la somme calculée à la position attendue.
#    - Ce mode écrase toujours la ligne de checksum existante à la position attendue si présente.
#
# 2. Vérification (`verify` ou `--verify`):
#    - Détermine la position attendue de la ligne CHKSUM (ligne 2 si la ligne 1 est un shebang, sinon ligne 1).
#    - Lit la ligne à cette position attendue pour y trouver une somme de contrôle stockée ("# CHKSUM: <valeur_stockee>").
#    - Si trouvée, supprime temporairement cette ligne CHKSUM (et la shebang si présente en ligne 1) pour obtenir le contenu original.
#    - Calcule la somme de contrôle SHA256 de ce contenu original.
#    - Compare la somme de contrôle calculée avec <valeur_stockee>.
#    - Indique si les sommes de contrôle correspondent ou non et quitte avec un code de succès (0) ou d'échec (1).
#
# 3. Mise à jour (`update` ou `--update`):
#    - Calcule la somme de contrôle SHA256 du contenu du fichier (en ignorant une éventuelle ligne CHKSUM existante).
#    - Si une ligne CHKSUM existe à la position attendue et que sa valeur correspond à la somme calculée, le fichier n'est pas modifié.
#    - Sinon (pas de ligne CHKSUM à la position attendue, ou valeur incorrecte), la ligne CHKSUM est insérée/mise à jour à la position attendue avec la somme de contrôle correcte.
#    - Note: Ce mode ne modifie pas la ligne shebang si elle est présente en ligne 1.
#
# USAGE:
#   ./checksum.sh <fichier> generate|verify|update
#
# EXEMPLES:
#   ./checksum.sh mon_fichier.txt generate
#   ./checksum.sh mon_fichier.txt verify
#   ./checksum.sh mon_fichier.txt update

set -e # Quitte immédiatement si une commande échoue
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

check_file_access() {
    local file="$1"
    [ -w "$file" ] || { echo -e "${COLOR_RED}Erreur${COLOR_RESET}: Pas de permission d'écriture pour '$file'."; exit 1; }
    [ -r "$file" ] || { echo -e "${COLOR_RED}Erreur${COLOR_RESET}: Pas de permission de lecture pour '$file'."; exit 1; }
}
# --- Fonctions d'aide ---

# Détermine la position attendue de la ligne CHKSUM et la ligne de début du contenu
# en fonction de la présence d'une shebang en première ligne.
# Définit les variables globales: CHECKSUM_LINE_NUM, CONTENT_START_LINE_NUM, IS_FIRST_LINE_SHEBANG
determine_line_numbers() {
    local file="$1"
    local first_line=$(head -n 1 "$file" 2>/dev/null || true)

    IS_FIRST_LINE_SHEBANG=false
    if [[ "$first_line" =~ ^#! ]]; then
        IS_FIRST_LINE_SHEBANG=true
        CHECKSUM_LINE_NUM=2
        CONTENT_START_LINE_NUM=3 # Content starts after shebang (1) and checksum (2)
    else
        IS_FIRST_LINE_SHEBANG=false
        CHECKSUM_LINE_NUM=1
        CONTENT_START_LINE_NUM=2 # Content starts after checksum (1)
    fi
}

# --- Variables globales déterminées par determine_line_numbers ---
CHECKSUM_LINE_NUM=1
CONTENT_START_LINE_NUM=2
IS_FIRST_LINE_SHEBANG=false

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

# Check file access permissions
check_file_access "$TARGET_FILE"

# --- Logique principale ---
if [[ "$MODE" == "generate" || "$MODE" == "--generate" ]]; then

    TEMP_FILE_A=$(mktemp) # Fichier temporaire pour le contenu sans l'ancienne ligne de checksum

    # Lire la première ligne du fichier cible
    FIRST_LINE_ORIGINAL=$(head -n 1 "$TARGET_FILE" 2>/dev/null || true)

    if [[ "$FIRST_LINE_ORIGINAL" == ${CHECKSUM_LINE_MARKER}* ]]; then
        echo "Ancienne ligne de checksum détectée en première ligne. Elle sera ignorée."
        if [[ $(wc -l < "$TARGET_FILE") -gt 1 ]]; then
            tail -n +2 "$TARGET_FILE" > "$TEMP_FILE_A"
        fi
    elif [[ "$FIRST_LINE_ORIGINAL" =~ ^#! ]]; then
        # Check if line 1 is a shebang and line 2 is a checksum
        local second_line=$(head -n 2 "$TARGET_FILE" | tail -n 1 2>/dev/null || true)
        if [[ "$second_line" == ${CHECKSUM_LINE_MARKER}* ]]; then
             echo "Ancienne ligne de checksum détectée en deuxième ligne (après shebang). Elle sera ignorée."
             tail -n +3 "$TARGET_FILE" > "$TEMP_FILE_A"
        else
            echo "Aucune ancienne ligne de checksum détectée en première ou deuxième ligne. Utilisation du contenu complet pour le checksum."
            cat "$TARGET_FILE" > "$TEMP_FILE_A"
        fi
    fi

    # Recalculate line numbers based on the *original* file content (before removing old checksum)
    determine_line_numbers "$TARGET_FILE"

    # Calculate the checksum of the content (stored in TEMP_FILE_A)
    # sha256sum handles an empty TEMP_FILE_A correctly (checksum will be the checksum of an empty file)
    CONTENT_CHKSUM=$(sha256sum "$TEMP_FILE_A" | awk '{print $1}')
    echo "Somme de contrôle calculée du contenu: $CONTENT_CHKSUM"

    NEW_CHECKSUM_LINE="${CHECKSUM_LINE_MARKER}${CONTENT_CHKSUM}"

    # Create the new final content in another temporary file
    TEMP_FILE_B=$(mktemp)

    if [ "$IS_FIRST_LINE_SHEBANG" == true ]; then
        # If line 1 was a shebang, write shebang (line 1), then new checksum (line 2), then content
        head -n 1 "$TARGET_FILE" > "$TEMP_FILE_B" # Original shebang line
        echo "$NEW_CHECKSUM_LINE" >> "$TEMP_FILE_B" # New checksum line
        cat "$TEMP_FILE_A" >> "$TEMP_FILE_B"       # Append content (which was in TEMP_FILE_A)
        echo "Nouvelle ligne de checksum insérée en ligne 2."
    else
        # If line 1 was not a shebang, write new checksum (line 1), then content
        echo "$NEW_CHECKSUM_LINE" > "$TEMP_FILE_B" # New checksum line
        cat "$TEMP_FILE_A" >> "$TEMP_FILE_B"       # Append content
        echo "Nouvelle ligne de checksum insérée en ligne 1."
    fi

    # Remplacer le fichier original
    mv "$TEMP_FILE_B" "$TARGET_FILE"
    # TEMP_FILE_B is renamed, so it won't be found by cleanup under its temp name.
    # TEMP_FILE_A will be cleaned by trap.

    echo "Fichier '$TARGET_FILE' mis à jour."

elif [[ "$MODE" == "verify" || "$MODE" == "--verify" ]]; then
    echo "Mode: Vérification de la somme de contrôle pour '$TARGET_FILE'."

    # Determine expected line numbers based on the current file content
    determine_line_numbers "$TARGET_FILE"

    # Get the line where the checksum is expected
    EXPECTED_CHKSUM_LINE=$(head -n "$CHECKSUM_LINE_NUM" "$TARGET_FILE" | tail -n 1 2>/dev/null || true)

    # Check if the expected line contains the checksum marker
    if [[ "$EXPECTED_CHKSUM_LINE" != ${CHECKSUM_LINE_MARKER}* ]]; then
        echo -e "${COLOR_RED}Erreur${COLOR_RESET}: Aucune ligne de somme de contrôle valide (format '${CHECKSUM_LINE_MARKER}...') trouvée en ligne $CHECKSUM_LINE_NUM de '$TARGET_FILE'."
        exit 1
    fi

    # Extract the stored checksum
    STORED_CHKSUM=$(echo "$EXPECTED_CHKSUM_LINE" | sed "s/^${CHECKSUM_LINE_MARKER}//")
    echo "Somme de contrôle stockée trouvée en ligne $CHECKSUM_LINE_NUM: $STORED_CHKSUM"

    # Valider la longueur et le format du checksum extrait (SHA256 = 64 caractères hex)
    if ! [[ "$STORED_CHKSUM" =~ ^[a-f0-9]{64}$ ]]; then
        echo -e "${COLOR_RED}Erreur${COLOR_RESET}: La somme de contrôle stockée '$STORED_CHKSUM' est malformée (doit être 64 caractères hexadécimaux)."
        exit 1
    fi

    # Create a temporary file with the content starting from CONTENT_START_LINE_NUM
    TEMP_FILE_A=$(mktemp)
    tail -n +"$CONTENT_START_LINE_NUM" "$TARGET_FILE" > "$TEMP_FILE_A"

    CALCULATED_CHKSUM=$(sha256sum "$TEMP_FILE_A" | awk '{print $1}')
    echo "Somme de contrôle calculée du contenu (à partir de la ligne $CONTENT_START_LINE_NUM): $CALCULATED_CHKSUM"

    if [ "$STORED_CHKSUM" == "$CALCULATED_CHKSUM" ]; then
        echo -e "${COLOR_GREEN}SUCCÈS:${COLOR_RESET} La somme de contrôle du fichier correspond à la somme de contrôle stockée."
        exit 0 # Succès
    else
        echo -e "${COLOR_RED}ÉCHEC:${COLOR_RESET} La somme de contrôle du fichier NE CORRESPOND PAS à la somme de contrôle stockée."
        echo -e "  Attendu (stocké en ligne $CHECKSUM_LINE_NUM) : ${COLOR_RED}$STORED_CHKSUM${COLOR_RESET}"
        echo -e "  Calculé (contenu à partir de ligne $CONTENT_START_LINE_NUM): ${COLOR_GREEN}$CALCULATED_CHKSUM${COLOR_RESET}"
        exit 1 # Échec
    fi

elif [[ "$MODE" == "update" || "$MODE" == "--update" ]]; then
    echo "Mode: Mise à jour de la somme de contrôle pour '$TARGET_FILE'."

    # Determine expected line numbers based on the current file content
    determine_line_numbers "$TARGET_FILE"

    TEMP_FILE_CONTENT=$(mktemp) # Fichier temporaire pour le contenu sans l'éventuelle ligne de checksum et shebang
    HAS_EXISTING_CHECKSUM_AT_EXPECTED_POS=false
    STORED_CHKSUM_VALUE=""

    # Get the line where the checksum is expected
    EXPECTED_CHKSUM_LINE=$(head -n "$CHECKSUM_LINE_NUM" "$TARGET_FILE" | tail -n 1 2>/dev/null || true)

    # Check if the expected line contains the checksum marker
    if [[ "$EXPECTED_CHKSUM_LINE" == ${CHECKSUM_LINE_MARKER}* ]]; then
        HAS_EXISTING_CHECKSUM_AT_EXPECTED_POS=true
        STORED_CHKSUM_VALUE=$(echo "$EXPECTED_CHKSUM_LINE" | sed "s/^${CHECKSUM_LINE_MARKER}//")
        # Valider le checksum stocké avant de continuer
        if ! [[ "$STORED_CHKSUM_VALUE" =~ ^[a-f0-9]{64}$ ]]; then
            echo "Ligne de checksum existante malformée en ligne $CHECKSUM_LINE_NUM: '$EXPECTED_CHKSUM_LINE'. Elle sera remplacée."
            HAS_EXISTING_CHECKSUM_AT_EXPECTED_POS=false # Treat as if it doesn't exist to force regeneration
        else
            echo "Ligne de checksum existante trouvée en ligne $CHECKSUM_LINE_NUM: $STORED_CHKSUM_VALUE"
        fi
    else
        echo "Aucune ligne de checksum détectée à la position attendue (ligne $CHECKSUM_LINE_NUM)."
    fi

    # Get the content for checksum calculation (skipping shebang if present and the expected checksum line if it exists)
    # This is tricky. We need to skip line 1 if it's a shebang, and skip CHECKSUM_LINE_NUM if it contains a valid checksum.
    # A simpler way is to just get the content starting from CONTENT_START_LINE_NUM, which already accounts for shebang and checksum position.
    tail -n +"$CONTENT_START_LINE_NUM" "$TARGET_FILE" > "$TEMP_FILE_CONTENT"

    # Calculate the checksum of the current content
    CURRENT_CONTENT_CHKSUM=$(sha256sum "$TEMP_FILE_CONTENT" | awk '{print $1}')
    echo "Somme de contrôle actuelle du contenu: $CURRENT_CONTENT_CHKSUM"

    if [ "$HAS_EXISTING_CHECKSUM_AT_EXPECTED_POS" == true ] && [ "$STORED_CHKSUM_VALUE" == "$CURRENT_CONTENT_CHKSUM" ]; then
        echo "La somme de contrôle est déjà à jour en ligne $CHECKSUM_LINE_NUM. Aucune modification nécessaire."
        # Clean up the content temp file before exiting
        rm -f "$TEMP_FILE_CONTENT"
        exit 0
    fi

    # If we reach here, we need to generate/update the checksum line
    if [ "$HAS_EXISTING_CHECKSUM_AT_EXPECTED_POS" == true ]; then
        echo "Mise à jour de la somme de contrôle en ligne $CHECKSUM_LINE_NUM (Ancienne: $STORED_CHKSUM_VALUE, Nouvelle: $CURRENT_CONTENT_CHKSUM)."
    else
        echo "Génération d'une nouvelle somme de contrôle en ligne $CHECKSUM_LINE_NUM: $CURRENT_CONTENT_CHKSUM."
    fi

    NEW_CHECKSUM_LINE="${CHECKSUM_LINE_MARKER}${CURRENT_CONTENT_CHKSUM}"

    TEMP_FILE_NEW=$(mktemp)

    if [ "$IS_FIRST_LINE_SHEBANG" == true ]; then
        # Write shebang (line 1), then new checksum (line 2), then content (from CONTENT_START_LINE_NUM)
        head -n 1 "$TARGET_FILE" > "$TEMP_FILE_NEW" # Original shebang line
        echo "$NEW_CHECKSUM_LINE" >> "$TEMP_FILE_NEW" # New checksum line
        cat "$TEMP_FILE_CONTENT" >> "$TEMP_FILE_NEW" # Append content
        echo "Nouvelle ligne de checksum insérée en ligne 2."
    else
        # Write new checksum (line 1), then content (from CONTENT_START_LINE_NUM)
        echo "$NEW_CHECKSUM_LINE" > "$TEMP_FILE_NEW" # New checksum line
        cat "$TEMP_FILE_CONTENT" >> "$TEMP_FILE_NEW" # Append content
        echo "Nouvelle ligne de checksum insérée en ligne 1."
    fi

    # Replace the original file
    mv "$TEMP_FILE_NEW" "$TARGET_FILE"
    # TEMP_FILE_NEW is renamed, so it won't be found by cleanup under its temp name.
    # TEMP_FILE_CONTENT will be cleaned by trap.

    echo "Fichier '$TARGET_FILE' mis à jour."

else
    echo -e "${COLOR_RED}Erreur${COLOR_RESET}: Mode '$MODE' inconnu."
    usage
fi
