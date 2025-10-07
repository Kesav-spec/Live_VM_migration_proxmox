#!/bin/bash
# migrate_vm.sh \E2\80\94 Migrate a VM between Proxmox nodes
# Usage: ./migrate_vm.sh <vmid> <destination_node>

set -e  # Exit on error

# === Input arguments ===
VMID="$1"
DEST_NODE="$2"

if [[ -z "$VMID" || -z "$DEST_NODE" ]]; then
  echo "Usage: $0 <vmid> <destination_node>"
  exit 1
fi

# === Prompt for SSH password ===
read -s -p "Enter SSH password for root@$DEST_NODE: " SSHPASS
echo

# === Check for sshpass ===
if ! command -v sshpass &> /dev/null; then
  echo "sshpass not found. Please install it: apt install sshpass"
  exit 1
fi

# === Create snapshot before move ===
SNAP_NAME="vm${VMID}-snap-$(date +%Y%m%d-%H%M%S)"
echo "Creating snapshot $SNAP_NAME for VM $VMID..."
qm snapshot "$VMID" "$SNAP_NAME"

# === Ensure destination image directory exists ===
echo "Ensuring /var/lib/vz/images/$VMID exists on $DEST_NODE..."
sshpass -p "$SSHPASS" ssh root@"$DEST_NODE" "mkdir -p /var/lib/vz/images/$VMID"

# === Transfer disk image ===
SRC_IMG="/var/lib/vz/images/$VMID/vm-${VMID}-disk-0.qcow2"
DST_IMG="/var/lib/vz/images/$VMID/"

echo "Transferring disk image to $DEST_NODE..."
sshpass -p "$SSHPASS" rsync -avz "$SRC_IMG" root@"$DEST_NODE":"$DST_IMG"


# === Copy VM config ===
echo "Copying config file..."
sshpass -p "$SSHPASS" scp "/etc/pve/qemu-server/${VMID}.conf" root@"$DEST_NODE":"/etc/pve/qemu-server/"

# === Comment out ISO line only in top-level config on destination node ===
echo "Removing ISO references from top-level config on $DEST_NODE..."
sshpass -p "$SSHPASS" ssh root@"$DEST_NODE" "
sed -i '/^\[.*\]/q; s/^\(ide2:.*iso.*\)/#\1/' /etc/pve/qemu-server/${VMID}.conf
"

# === Start VM on destination ===
echo "Starting VM $VMID on $DEST_NODE..."
sshpass -p "$SSHPASS" ssh root@"$DEST_NODE" "qm start $VMID"

# === Then shutdown VM on Node-1 ===
echo "Shutting down VM $VMID on this node (Node-1)..."
qm shutdown "$VMID"

echo "Migration of VM $VMID completed successfully to $DEST_NODE!"



