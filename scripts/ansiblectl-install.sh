#!/bin/bash

USER="ansible"

# 1. Install Ansible and dependencies
apt-get update -q
apt-get install -y ansible sshpass git

# 2. Create the user if it doesn't exist
if ! id -u "$USER" > /dev/null 2>&1; then
    useradd -m -s /bin/bash "$USER"
fi

# 3. Generate SSH Key (Ed25519) as the user, with no passphrase
# This runs inside the user's shell to ensure correct ownership
su - "$USER" -c "if [ ! -f ~/.ssh/id_ed25519 ]; then ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519; fi"

# 4. Output the Public Key
echo "-------------------------------------------------------"
echo "Control Node Setup Complete."
echo "Copy the key below into your Target Node bootstrap script:"
echo "-------------------------------------------------------"
cat "/home/$USER/.ssh/id_ed25519.pub"
echo "-------------------------------------------------------"
