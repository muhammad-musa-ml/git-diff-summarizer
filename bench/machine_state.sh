#!/usr/bin/env bash
# Writes bench/results/machine-<label>.txt: what the machine was doing around
# a measurement pass. Windows host (PowerShell is used for CPU and memory).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
label=${1:?usage: machine_state.sh LABEL}
out=$root/bench/results/machine-$label.txt
mkdir -p "$root/bench/results"

ps() {
    powershell.exe -NoProfile -Command "$1" | tr -d '\r'
}

others=$(docker ps --format '{{.Names}}' | grep -vc '^git-diff-summarizer' || true)
{
    echo "time: $(date -u +%FT%TZ)"
    echo "cpu: $(ps '(Get-CimInstance Win32_Processor).Name')"
    echo "logical cpus: $(ps '(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors')"
    echo "os: $(ps '(Get-CimInstance Win32_OperatingSystem).Caption + " " + (Get-CimInstance Win32_OperatingSystem).Version')"
    echo "cpu busy percent (3 s sample): $(ps '[math]::Round((Get-Counter "\Processor(_Total)\% Processor Time" -SampleInterval 3 -MaxSamples 1).CounterSamples.CookedValue, 1)')"
    echo "free physical memory (MB): $(ps '[math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)')"
    echo "total physical memory (MB): $(ps '[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)')"
    echo "docker engine: $(docker version --format '{{.Server.Version}}')"
    echo "docker vm: $(docker info --format 'cpus={{.NCPU}} memory_bytes={{.MemTotal}}')"
    echo "running containers that are not this project's: $others"
    echo "running containers of this project: $(docker ps --format '{{.Names}}' | grep -c '^git-diff-summarizer' || true)"
} >"$out"
cat "$out"
