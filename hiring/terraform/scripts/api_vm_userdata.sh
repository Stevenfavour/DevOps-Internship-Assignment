#!/bin/bash
set -e

# Install dependencies
sudo apt-get update && sudo apt-get install -y curl jq git

# Install III engine
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/ubuntu/.bashrc

# Clone repo
git clone --depth 1 --filter=blob:none --sparse https://github.com/Alchemyst-ai/hiring.git /home/ubuntu/hiring
cd /home/ubuntu/hiring
git sparse-checkout set may-2026/devops
cd may-2026/devops/quickstart

# Write config.yaml
cat > config.yaml << 'EOF'
workers:
  - name: iii-observability
    config:
      enabled: true
      service_name: iii
      exporter: memory
      memory_max_spans: 10000
      logs_enabled: true
      logs_console_output: true
      sampling_ratio: 1.0
  - name: iii-http
    config:
      port: 3111
      host: 0.0.0.0
      default_timeout: 120000
      cors:
        allowed_origins:
          - '*'
        allowed_methods:
          - GET
          - POST
          - PUT
          - DELETE
          - OPTIONS
EOF

# Start engine as ubuntu user
sudo -u ubuntu bash -c 'export PATH="$HOME/.local/bin:$PATH" && cd /home/ubuntu/hiring/may-2026/devops/quickstart && iii --config config.yaml &'
