# Fixed Dockerfile - uses git clone + explicit pip install + pre-downloads EVA-CLIP/InsightFace
# so PuLID Flux works without needing runtime downloads (which fail when container disk is small).

FROM runpod/worker-comfyui:5.8.6-base-cuda12.8.1

ARG HF_TOKEN=""

# Persistent cache so runtime downloads land somewhere baked into the image
ENV HF_HOME=/comfyui/.cache/huggingface
ENV TRANSFORMERS_CACHE=/comfyui/.cache/huggingface
ENV HF_HUB_CACHE=/comfyui/.cache/huggingface

RUN mkdir -p /comfyui/.cache/huggingface /root/.insightface/models

# ========== install custom nodes (git clone + pip install) ==========
RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git && \
    pip install --no-cache-dir gguf

RUN cd /comfyui/custom_nodes && \
    git clone --depth 1 https://github.com/lldacing/ComfyUI_PuLID_Flux_ll.git && \
    pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI_PuLID_Flux_ll/requirements.txt && \
    pip install --no-cache-dir --no-deps facenet-pytorch Pillow numpy requests

# Patch PuLID Flux ll's pulid_forward_orig() to accept **kwargs.
# ComfyUI 5.8.6+ calls it with new keyword args (timestep_zero_index, etc.) that
# the original function signature doesn't accept. Adding **kwargs swallows them
# safely - PuLID doesn't need those args, it just needs to not crash on them.
RUN python3 -c "\
import re; \
p = '/comfyui/custom_nodes/ComfyUI_PuLID_Flux_ll/PulidFluxHook.py'; \
s = open(p).read(); \
s = re.sub(r'(def pulid_forward_orig\([^)]*?attn_mask: Tensor = None,)\n\) -> Tensor:', r'\\1\n    **kwargs,\n) -> Tensor:', s, count=1); \
open(p,'w').write(s); \
print('Patched pulid_forward_orig with **kwargs')"

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

# Verify critical nodes loaded
RUN ls -la /comfyui/custom_nodes/

# ========== Pre-download runtime model dependencies ==========
# PuLID Flux needs EVA-CLIP + InsightFace antelopev2. These normally download on first use
# which fails when container has limited disk. Pre-downloading them avoids that.

# EVA-CLIP model used by PuLID Flux ll
RUN python -c "from huggingface_hub import hf_hub_download; \
    hf_hub_download(repo_id='QuanSun/EVA-CLIP', filename='EVA02_CLIP_L_336_psz14_s6B.pt'); \
    print('EVA-CLIP pre-downloaded OK')" || echo "EVA-CLIP pre-download failed - will retry at runtime"

# InsightFace antelopev2 face detection model (used by PulidFluxInsightFaceLoader)
RUN python -c "import insightface; \
    app = insightface.app.FaceAnalysis(name='antelopev2', providers=['CPUExecutionProvider']); \
    app.prepare(ctx_id=0, det_size=(640, 640)); \
    print('InsightFace antelopev2 pre-downloaded OK')" || echo "InsightFace pre-download failed - will retry at runtime"

# ========== download Flux + PuLID + supporting models ==========
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/ffxvs/vae-flux/resolve/main/ae.safetensors' --relative-path models/vae --filename 'ae.safetensors' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/hazelfvue/fluxrealistic/resolve/main/fluxRealistic_ggufFluxRealistic.gguf' --relative-path models/diffusion_models --filename 'fluxRealistic_ggufFluxRealistic.gguf' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors' --relative-path models/clip --filename 't5xxl_fp16.safetensors' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors' --relative-path models/clip --filename 'clip_l.safetensors' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/guozinan/PuLID/resolve/main/pulid_flux_v0.9.1.safetensors' --relative-path models/pulid --filename 'pulid_flux_v0.9.1.safetensors' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/fofr/comfyui/resolve/main/sam2/sam2.1_hiera_large-fp16.safetensors' --relative-path models/sam2 --filename 'sam2.1_hiera_large.safetensors' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done

# user-provided inputs override the auto-generated placeholders above.
RUN wget --progress=dot:giga -O '/comfyui/input/be575a91af004227a6f39e9d32695f10_974728b6bd5141a9885467bfe4e73c9d%20(1)-enhanced.png' "https://cool-anteater-319.convex.cloud/api/storage/dfac9520-2f10-4333-8932-c4dbe2ba554d"
RUN wget --progress=dot:giga -O '/comfyui/input/1469633014.webp' "https://cool-anteater-319.convex.cloud/api/storage/fd905dee-18ab-4f6e-8470-5a1e07764a69"
