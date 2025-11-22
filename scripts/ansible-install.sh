if ! id -u "$USER" > /dev/null 2>&1; then
    useradd -m -s /bin/bash "$USER"
fi

# 2. Setup passwordless sudo
echo "$USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USER"
chmod 0440 "/etc/sudoers.d/$USER"

# 3. Setup SSH directory
mkdir -p "/home/$USER/.ssh"

# 4. Add key if not present
if ! grep -qF "$SSH_KEY" "/home/$USER/.ssh/authorized_keys"; then
    echo "$SSH_KEY" >> "/home/$USER/.ssh/authorized_keys"
fi

# 5. Fix permissions
chown -R "$USER:$USER" "/home/$USER/.ssh"
chmod 700 "/home/$USER/.ssh"
chmod 600 "/home/$USER/.ssh/authorized_keys"

echo "Setup complete for user: $USER"
