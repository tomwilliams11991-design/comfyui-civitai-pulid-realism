# Fixed Dockerfile - uses git clone + explicit pip install instead of
# unreliable `comfy node install` calls. Fixes "UnetLoaderGGUF not found"
# runtime error from the wizard-generated original.

FROM runpod/worker-comfyui:5.8.4-base

ARG HF_TOKEN=""

# ========== install custom nodes (git clone + pip install) ==========
# Using git clone is more reliable than `comfy node install` because:
# 1. We control the exact commit
# 2. We explicitly install Python requirements
# 3. Failures are visible immediately

RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git && \
    pip install --no-cache-dir gguf

RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/lldacing/ComfyUI_PuLID_Flux_ll.git && \
    (pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI_PuLID_Flux_ll/requirements.txt || \
     pip install --no-cache-dir facexlib onnxruntime-gpu insightface timm)

RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-Florence2.git && \
    (pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-Florence2/requirements.txt || \
     pip install --no-cache-dir transformers einops timm)

RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-segment-anything-2.git && \
    (pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-segment-anything-2/requirements.txt || \
     pip install --no-cache-dir sam2)

RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git

RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git

RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/chflame163/ComfyUI_LayerStyle.git && \
    (pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI_LayerStyle/requirements.txt || true)

# Verify critical nodes loaded (will print to build log)
RUN ls -la /comfyui/custom_nodes/

# ========== download models ==========
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/ffxvs/vae-flux/resolve/main/ae.safetensors' --relative-path models/vae --filename 'ae.safetensors' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/hazelfvue/fluxrealistic/resolve/main/fluxRealistic_ggufFluxRealistic.gguf' --relative-path models/diffusion_models --filename 'fluxRealistic_ggufFluxRealistic.gguf' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors' --relative-path models/clip --filename 't5xxl_fp16.safetensors' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors' --relative-path models/clip --filename 'clip_l.safetensors' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/guozinan/PuLID/resolve/main/pulid_flux_v0.9.1.safetensors' --relative-path models/pulid --filename 'pulid_flux_v0.9.1.safetensors' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/fofr/comfyui/resolve/main/sam2/sam2.1_hiera_large-fp16.safetensors' --relative-path models/sam2 --filename 'sam2.1_hiera_large.safetensors' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done

# user-provided inputs override the auto-generated placeholders above.
RUN wget --progress=dot:giga -O '/comfyui/input/be575a91af004227a6f39e9d32695f10_974728b6bd5141a9885467bfe4e73c9d%20(1)-enhanced.png' "https://cool-anteater-319.convex.cloud/api/storage/dfac9520-2f10-4333-8932-c4dbe2ba554d"
RUN wget --progress=dot:giga -O '/comfyui/input/1469633014.webp' "https://cool-anteater-319.convex.cloud/api/storage/fd905dee-18ab-4f6e-8470-5a1e07764a69"
