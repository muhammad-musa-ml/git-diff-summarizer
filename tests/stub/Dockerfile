FROM ubuntu:24.04

ENV DIFFSUM_MODEL_NAME=stub \
    LLAMAFILE=/opt/model/llamafile \
    MODEL_GGUF=/opt/model/model.gguf

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/model
COPY llamafile stub_model.py ./
RUN echo stub > model.gguf
