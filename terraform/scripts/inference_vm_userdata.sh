#!/bin/bash
set -e

# Install dependencies
sudo apt-get update && sudo apt-get install -y curl jq git python3-pip

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
cd may-2026/devops/quickstart/workers/inference-worker

# Install Python dependencies
python3 -m pip install torch --index-url https://download.pytorch.org/whl/cpu
python3 -m pip install --upgrade --force-reinstall "gguf>=0.10.0"
python3 -m pip install "jinja2>=3.1.0" --upgrade
python3 -m pip install transformers accelerate

# Create run.py wrapper
# Fixes a bug in transformers where gguf is not in PACKAGE_DISTRIBUTION_MAPPING,
# causing is_gguf_available() to return False even when gguf>=0.10.0 is installed.
cat > run.py << 'EOF'
import importlib.metadata
import transformers.utils.import_utils as tu

tu.PACKAGE_DISTRIBUTION_MAPPING["gguf"] = ["gguf"]

import inference_worker
EOF

# Start worker
sudo -u ubuntu bash -c 'export PATH="$HOME/.local/bin:$PATH" && export III_URL=ws://${api_private_ip}:49134 && cd /home/ubuntu/hiring/may-2026/devops/quickstart/workers/inference-worker && python3 run.py &'
