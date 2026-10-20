#!/usr/bin/env bash
# Independent AI environment; never modify the original Stage-3 environment.
set -euo pipefail
test "$(hostname -s)" = jzm
ai_root=/home/jzm123/AAA_ZTEproject/RIS_stage3_ai
ai_env="$ai_root/.venv311"
mkdir -p "$ai_root"
if [ ! -x "$ai_env/bin/python" ]; then
  /home/jzm123/AAA_ZTEproject/RIS_stage3/.venv311/bin/python -m venv --without-pip "$ai_env"
fi
/home/jzm123/miniconda3/bin/python -m pip --python "$ai_env/bin/python" install \
  numpy==2.2.6 scipy==1.15.3 matplotlib==3.10.3 threadpoolctl==3.6.0
/home/jzm123/miniconda3/bin/python -m pip --python "$ai_env/bin/python" install \
  torch==2.8.0 --index-url https://download.pytorch.org/whl/cu126
"$ai_env/bin/python" -c 'import torch; print("TORCH", torch.__version__, "CUDA", torch.version.cuda, "AVAILABLE", torch.cuda.is_available()); assert torch.cuda.is_available()'
