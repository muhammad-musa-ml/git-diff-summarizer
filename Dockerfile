ARG BASE=git-diff-summarizer-model:latest
FROM ${BASE}

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates curl jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY scripts/ ./

ENTRYPOINT ["/app/summarize.sh"]
