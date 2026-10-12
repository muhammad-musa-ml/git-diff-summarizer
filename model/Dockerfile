FROM ubuntu:24.04

ARG MODEL_NAME=gemma-4-E2B-it-Q5_K_M
ENV DIFFSUM_MODEL_NAME=$MODEL_NAME \
    LLAMAFILE=/opt/model/llamafile \
    MODEL_GGUF=/opt/model/model.gguf

WORKDIR /opt/model

# model/fetch.sh puts both files in model/cache first, checksummed. The runtime
# comes before the 3.3 GB weights so a rebuild after a runtime bump does not
# re-copy them.
COPY cache/llamafile ./llamafile
COPY cache/model.gguf ./model.gguf

# A llamafile is an actually-portable executable. The kernel cannot exec it
# directly (no binfmt handler in the container), so it has to be started
# through a shell, which is what the shell fallback of execve gives us; callers
# use `sh -c "$LLAMAFILE ..."`.
CMD ["sh", "-c", "$LLAMAFILE --server --host 0.0.0.0 --port 8080 -m $MODEL_GGUF"]
