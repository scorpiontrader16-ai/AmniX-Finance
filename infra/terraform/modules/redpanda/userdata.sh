#!/bin/bash
set -euo pipefail

# ── Install Redpanda ─────────────────────────────────────────────────────
curl -1sLf \
  'https://dl.redpanda.com/nzc4ZYQK3WRGd9sy/redpanda/cfg/setup/bash.deb.sh' \
  | sudo -E bash

sudo apt-get install -y redpanda

# ── Configure Redpanda ───────────────────────────────────────────────────
sudo rpk redpanda config set redpanda.node_id ${broker_id}
sudo rpk redpanda config set redpanda.data_directory /var/lib/redpanda/data

# Tiered Storage
sudo rpk redpanda config set \
  redpanda.cloud_storage_enabled true
sudo rpk redpanda config set \
  redpanda.cloud_storage_bucket ${tiered_storage_bucket}
sudo rpk redpanda config set \
  redpanda.cloud_storage_region ${aws_region}

# ── Start Redpanda ───────────────────────────────────────────────────────
sudo systemctl enable redpanda
sudo systemctl start redpanda
