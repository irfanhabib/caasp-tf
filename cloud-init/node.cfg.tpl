#cloud-config

# set locale
locale: fr_FR.UTF-8

# set timezone
timezone: Europe/Paris

# set root password
chpasswd:
  list: |
    root:${password}
  expire: False

users:
  - name: qa
    gecos: User
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    groups: users
    lock_passwd: false
    passwd: ${password}

# set as admin node
suse_caasp:
  role: cluster
  admin_node: ${admin_node_ip}

final_message: "The system is finally up, after $UPTIME seconds"
