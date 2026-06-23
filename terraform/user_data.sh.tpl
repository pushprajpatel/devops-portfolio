#!/bin/bash
set -ex

# Amazon Linux 2023
dnf update -y
dnf install -y docker git
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Docker Compose plugin (not bundled with the docker package on AL2023)
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

git clone ${github_repo_url} /opt/app
cd /opt/app/ai-search-service

# First boot pulls the qwen2.5:7b model (~4.7GB) — this can take several
# minutes depending on network speed, well before /health responds.
docker compose up -d
