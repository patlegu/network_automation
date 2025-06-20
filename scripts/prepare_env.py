import os
import shutil
import stat
import subprocess


HOME_DIR = os.path.expanduser("~")
ANSIBLE_CONFIG_SOURCE = "/root/ansible.cfg"  # Chemin où ansible.cfg est copié par le Dockerfile
ANSIBLE_CONFIG_DEST = os.path.join(HOME_DIR, ".ansible.cfg")
SSH_DIR = os.path.join(HOME_DIR, ".ssh")
SSH_CONFIG_FILE = os.path.join(SSH_DIR, "config")
PLAYBOOKS_DIR = os.path.join(HOME_DIR, "playbooks")
PLAYBOOKS_GIT_REPO_URL = os.environ.get("PLAYBOOKS_GIT_REPO_URL")

def create_directory(path):
    """Crée un répertoire s'il n'existe pas."""
    if not os.path.exists(path):
        print(f"===> Création du répertoire : {path}")
        os.makedirs(path)
        # Pour le répertoire .ssh, nous devons définir des permissions spécifiques
        if path == SSH_DIR:
            os.chmod(path, stat.S_IRWXU) # 0700
    else:
        print(f"===> Répertoire existant : {path}")

def setup_ansible_config():
    """Configure le fichier ansible.cfg."""
    if os.path.exists(ANSIBLE_CONFIG_SOURCE):
        print(f"===> Copie de {ANSIBLE_CONFIG_SOURCE} vers {ANSIBLE_CONFIG_DEST}")
        shutil.copy(ANSIBLE_CONFIG_SOURCE, ANSIBLE_CONFIG_DEST)
        # Assurez-vous que le propriétaire est root et que les permissions sont raisonnables
        os.chown(ANSIBLE_CONFIG_DEST, 0, 0) # root:root
        os.chmod(ANSIBLE_CONFIG_DEST, stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH) # 0644
    else:
        print(f"===> ATTENTION: Fichier source ansible.cfg non trouvé à {ANSIBLE_CONFIG_SOURCE}")
        print(f"===> Création d'un fichier ansible.cfg par défaut à {ANSIBLE_CONFIG_DEST}")
        default_ansible_cfg_content = """
[defaults]
inventory = ~/playbooks/hosts
host_key_checking = False
# Décommentez et ajustez si vous utilisez un interpréteur Python spécifique dans un venv Ansible
# ansible_python_interpreter = /root/venv/bin/python
ansible_python_interpreter = /usr/bin/python3
"""
        with open(ANSIBLE_CONFIG_DEST, "w") as f:
            f.write(default_ansible_cfg_content)
        os.chown(ANSIBLE_CONFIG_DEST, 0, 0)
        os.chmod(ANSIBLE_CONFIG_DEST, stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH) # 0644

def setup_ssh_config():
    """Configure le fichier ~/.ssh/config."""
    create_directory(SSH_DIR)
    ssh_config_content = """
Host *
    KexAlgorithms diffie-hellman-group1-sha1,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group-exchange-sha256,diffie-hellman-group14-sha1
    Ciphers 3des-cbc,aes128-cbc,aes128-ctr,aes256-ctr
    UserKnownHostsFile /dev/null
    StrictHostKeyChecking no
"""
    # UserKnownHostsFile /dev/null et StrictHostKeyChecking no sont souvent utilisés
    # dans des environnements de test/dev pour éviter les prompts, mais soyez conscient des implications de sécurité.

    if not os.path.exists(SSH_CONFIG_FILE):
        print(f"===> Création du fichier SSH config : {SSH_CONFIG_FILE}")
        with open(SSH_CONFIG_FILE, "w") as f:
            f.write(ssh_config_content)
        os.chmod(SSH_CONFIG_FILE, stat.S_IRUSR | stat.S_IWUSR) # 0600
    else:
        print(f"===> Fichier SSH config existant : {SSH_CONFIG_FILE}")
        # Vous pourriez vouloir vérifier/mettre à jour le contenu ici si nécessaire

def clone_playbooks_repo():
    """Clone un dépôt Git de playbooks si PLAYBOOKS_GIT_REPO_URL est défini et que le répertoire est vide ou non-git."""
    if PLAYBOOKS_GIT_REPO_URL:
        print(f"===> Vérification du dépôt de playbooks à {PLAYBOOKS_DIR} pour l'URL : {PLAYBOOKS_GIT_REPO_URL}")
        # Vérifier si le répertoire est vide ou n'est pas un dépôt git
        is_empty = not os.listdir(PLAYBOOKS_DIR)
        is_git_repo = os.path.exists(os.path.join(PLAYBOOKS_DIR, ".git"))

        if is_empty or not is_git_repo:
            if not is_empty and not is_git_repo:
                print(f"===> ATTENTION: {PLAYBOOKS_DIR} n'est pas vide et n'est pas un dépôt Git. Le clonage va échouer si le répertoire n'est pas vide.")
                # Pourrait être plus sûr de ne pas cloner si le répertoire n'est pas vide et n'est pas un .git
                # Ou de supprimer le contenu, mais c'est risqué. Pour l'instant, on laisse git gérer l'erreur.

            print(f"===> Clonage du dépôt de playbooks depuis {PLAYBOOKS_GIT_REPO_URL} dans {PLAYBOOKS_DIR}...")
            try:
                subprocess.run(["git", "clone", PLAYBOOKS_GIT_REPO_URL, PLAYBOOKS_DIR], check=True)
                print("===> Dépôt de playbooks cloné avec succès.")
            except subprocess.CalledProcessError as e:
                print(f"===> ERREUR: Échec du clonage du dépôt de playbooks : {e}")
            except FileNotFoundError:
                print("===> ERREUR: La commande 'git' n'a pas été trouvée. Veuillez l'installer dans le conteneur.")
        else:
            print(f"===> Le répertoire {PLAYBOOKS_DIR} contient déjà un dépôt Git ou n'est pas vide. Clonage ignoré.")
    else:
        print("===> Variable d'environnement PLAYBOOKS_GIT_REPO_URL non définie. Clonage du dépôt de playbooks ignoré.")

def main():
    """Fonction principale pour préparer l'environnement."""
    print("===> Démarrage du script de préparation de l'environnement root...")

    # Créer le répertoire pour les playbooks Ansible
    create_directory(PLAYBOOKS_DIR)
    clone_playbooks_repo()

    # Configurer Ansible
    setup_ansible_config()

    # Configurer SSH
    setup_ssh_config()

    print("===> Préparation de l'environnement root terminée.")

if __name__ == "__main__":
    main()
