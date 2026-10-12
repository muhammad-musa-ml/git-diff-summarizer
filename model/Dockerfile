FROM ubuntu:24.04

ARG MODEL_NAME=gemma-4-E2B-it-Q5_K_M
ENV DIFFSUM_MODEL_NAME=$MODEL_NAME \
    LLAMAFILE=/opt/model/llamafile \
    MODEL_GGUF=/opt/model/model.gguf

WORKDIR /opt/model

# model/fetch.sh puts both files in model/cache first, checksummed. The runtime
# comes before the 3.3 GB weights so a bump of the runtime does not re-copy them.
COPY cache/llamafile ./llamafile
COPY cache/model.gguf ./model.gguf

# A llamafile starts with a shell stub and an APE header the kernel has no
# loader for, so exec'ing it directly fails with "not found". Handing it to sh
# as a script works, hence `sh $LLAMAFILE` rather than running the file.
CMD ["sh", "-c", "sh $LLAMAFILE -m $MODEL_GGUF --server --host 0.0.0.0 --port 8080"]
