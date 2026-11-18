#!/usr/bin/env bash
# One-shot setup for a fresh Ubuntu 24.04 bastion: swap, Docker, Terraform, AWS CLI.
# Run as the normal user (ubuntu), NOT as root:   bash scripts/bootstrap-bastion.sh
# Safe to run twice: every step is skipped when it is already done.
set -euo pipefail

SWAP_SIZE="${SWAP_SIZE:-2G}"
# Works both when run by hand (as ubuntu) and from EC2 user_data (as root).
# Under user_data $USER is "root", so when running as root fall back to "ubuntu".
if [ "$(id -u)" -eq 0 ]; then
  TARGET_USER="${SUDO_USER:-ubuntu}"
else
  TARGET_USER="$USER"
fi

echo "==> 0/4 Base packages"
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg unzip

echo "==> 1/4 Swap ($SWAP_SIZE)"
if swapon --show | grep -q '/swapfile'; then
  echo "swap already enabled, skipping"
else
  [ -f /swapfile ] || sudo fallocate -l "$SWAP_SIZE" /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null

echo "==> 2/4 Docker"
if command -v docker >/dev/null; then
  echo "docker already installed, skipping"
else
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
sudo usermod -aG docker "$TARGET_USER"

echo "==> 3/4 Terraform"
if command -v terraform >/dev/null; then
  echo "terraform already installed, skipping"
else
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y terraform
fi

echo "==> 4/4 AWS CLI v2"
if command -v aws >/dev/null; then
  echo "aws cli already installed, skipping"
else
  tmp="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "$tmp/awscliv2.zip"
  unzip -q "$tmp/awscliv2.zip" -d "$tmp"
  sudo "$tmp/aws/install"
  rm -rf "$tmp"
fi

echo
echo "==== Done ===="
free -h | sed -n '1,3p'
docker --version || true
terraform version | head -1
aws --version
echo
echo "IMPORTANT: log out and SSH in again (or run: newgrp docker) so the 'docker' group takes effect."
