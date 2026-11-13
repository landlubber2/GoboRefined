# Lab helper: let the host SSH into the live session. In the guest: wget -qO- http://10.0.2.2:8766/lab-ssh.sh | sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
wget -qO ~/.ssh/authorized_keys http://10.0.2.2:8766/k && chmod 600 ~/.ssh/authorized_keys
ssh-keygen -A > /dev/null
"$(command -v sshd)" && echo "sshd started"
