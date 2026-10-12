FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends bats shellcheck git jq curl python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
