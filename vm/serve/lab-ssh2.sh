# Lab helper for an INSTALLED system: run as root (sudo sh this-file). Lets the host SSH in as root.
mkdir -p /Users/root/.ssh && chmod 700 /Users/root /Users/root/.ssh
wget -qO /Users/root/.ssh/authorized_keys http://10.0.2.2:8766/k && chmod 600 /Users/root/.ssh/authorized_keys
ssh-keygen -A > /dev/null
"$(command -v sshd)" && echo "sshd started"
