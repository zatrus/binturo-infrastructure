#!/usr/bin/env python3
"""Restricted SSH command for exporting a local Prometheus snapshot."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
from urllib.request import Request, urlopen

PORT = 19090
CONTAINER = "binturo-prometheus"
EXPORT_ROOT = Path.home() / ".binturo-prometheus-export"


def main():
    command = os.environ.get("SSH_ORIGINAL_COMMAND", "").split()
    if command != ["sync"]:
        raise SystemExit("Expected sync")
    if EXPORT_ROOT.exists():
        shutil.rmtree(EXPORT_ROOT)
    EXPORT_ROOT.mkdir(mode=0o700)
    request = Request(
        f"http://127.0.0.1:{PORT}/api/v1/admin/tsdb/snapshot",
        data=b"",
        method="POST",
    )
    with urlopen(request, timeout=120) as response:
        name = json.load(response)["data"]["name"]
    if not name or "/" in name or name in {".", ".."}:
        raise RuntimeError("Invalid snapshot name")
    docker_env = os.environ.copy()
    docker_env["DOCKER_HOST"] = f"unix:///run/user/{os.getuid()}/docker.sock"
    try:
        try:
            subprocess.run(
                ["docker", "cp", f"{CONTAINER}:/prometheus/snapshots/{name}/.", str(EXPORT_ROOT)],
                check=True, env=docker_env,
            )
        finally:
            subprocess.run(
                ["docker", "exec", CONTAINER, "rm", "-rf", f"/prometheus/snapshots/{name}"],
                check=True, env=docker_env,
            )
        with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as archive:
            for path in EXPORT_ROOT.iterdir():
                archive.add(path, arcname=path.name, recursive=True)
    finally:
        shutil.rmtree(EXPORT_ROOT)


if __name__ == "__main__":
    main()
