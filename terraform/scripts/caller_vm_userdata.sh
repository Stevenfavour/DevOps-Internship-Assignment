#!/bin/bash
set -e

# Install dependencies
sudo apt-get update && sudo apt-get install -y curl jq git

# Install Node.js 18 (remove conflicting old version first)
sudo apt-get remove -y nodejs libnode-dev libnode72 || true
sudo apt-get autoremove -y
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install III engine
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/ubuntu/.bashrc

# Set III_URL permanently — points to the API VM's III engine
echo 'export III_URL=ws://${api_private_ip}:49134' >> /home/ubuntu/.bashrc

# Clone repo
git clone --depth 1 --filter=blob:none --sparse https://github.com/Alchemyst-ai/hiring.git /home/ubuntu/hiring
cd /home/ubuntu/hiring
git sparse-checkout set may-2026/devops
cd may-2026/devops/quickstart/workers/caller-worker

# Install and build TypeScript worker
npm install
npm update iii-sdk
npm run build

# Start worker — Node 18 requires --experimental-global-webcrypto for crypto.randomUUID()
sudo -u ubuntu bash -c 'export PATH="$HOME/.local/bin:$PATH" && export III_URL=ws://${api_private_ip}:49134 && cd /home/ubuntu/hiring/may-2026/devops/quickstart/workers/caller-worker && node --experimental-global-webcrypto dist/worker.js &'
