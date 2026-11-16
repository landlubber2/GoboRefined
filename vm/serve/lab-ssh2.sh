# Lab helper for an INSTALLED system: run as root (sudo sh this-file). Lets the host SSH in as root.
mkdir -p /Users/root/.ssh && chmod 700 /Users/root /Users/root/.ssh
wget -qO /Users/root/.ssh/authorized_keys http://10.0.2.2:8766/k && chmod 600 /Users/root/.ssh/authorized_keys
ssh-keygen -A > /dev/null
"$(command -v sshd)" && echo "sshd started"
# 0.9.1: the firewall drops new connections; let the lab host (VirtualBox NAT 10.0.2.2) in (lab only)
command -v iptables > /dev/null && { iptables -C INPUT -s 10.0.2.2 -p tcp --dport 22 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -s 10.0.2.2 -p tcp --dport 22 -j ACCEPT; }
