#!/usr/bin/env bash

# This script search for odoo forks that contains enterprise revisions
# Culture point if you know why this script has this name.

set -euo pipefail

test "${DEBUG:-0}" != 0 && set -x

: "${GH_TOKEN:?Please set a GH_TOKEN environment variable}"

# Ensure minimal git version
printf '%s\n%s\n' 2.23 "$(git --version | cut -d" " -f3)" | sort --check=quiet --version-sort || \
    { echo "ERROR: outdated git version. Git >= 2.23 is required." >&2; exit 1; }

workdir="${XDG_CACHE_HOME:-${HOME}/.cache}/Harve"
mkdir -p "$workdir"
venv="${workdir}/.venv"

if [[ ! -d "$workdir/.git" ]]; then
    git init -q "$workdir"
fi

if [[ ! -d "$venv" ]]; then
    python3 -m venv "$venv"
    "$venv/bin/pip" install -U pip
    "$venv/bin/pip" install PyGithub
fi

# Generate config file with remotes
"$venv/bin/python" > "$workdir/.git/config" <<EOP
#!/usr/bin/env python3
import os
import sys
from github import Github


REMOTE = """\
[remote "{remote}"]
    url = {url}
    fetch = +refs/heads/*:refs/remotes/{remote}/*
    fetch = +refs/pull/*/head:refs/remotes/{remote}/pr/*
"""


def forks(repo):
    print(REMOTE.format(remote=repo.full_name, url=repo.git_url))
    if not repo.forks_count:
        return
    for frk in repo.get_forks():
        try:
            forks(frk)
        except Exception as e:
            print(f"cannot get {frk.full_name}: {e}", file=sys.stderr)

# Token is required to get over the low rate-limit of unauthentified requests
gh = Github(os.getenv("GH_TOKEN"))
forks(gh.get_repo("odoo/odoo"))
EOP

git="git -C $workdir/.git"

jobs=$(( ($(nproc) + 1) / 2))

# some repo may not be accessible, ignore errors
$git fetch --all --prune --quiet --no-auto-gc --multiple --jobs="$jobs" 2>/dev/null || true

rm -f "$workdir/.git/gc.log"
$git gc --quiet

set -x
# The search for the hash will return an error if not found. That the inverse of what we want.
$git branch --all --contains 4295585aff34ba9881ed7f64bce3481e3d217dcd || exit 0
exit 1
