#!/usr/bin/env bash

# This script search for odoo forks that contains enterprise revisions
# Culture point if you know why this script has this name.

set -euo pipefail

: "${GH_TOKEN:?Please set a GH_TOKEN environment variable}"

test "${DEBUG:-0}" != 0 && set -x

# Ensure minimal git version
printf '%s\n%s\n' 2.23 "$(git --version | cut -d" " -f3)" | sort --check=quiet --version-sort || \
    { echo "ERROR: outdated git version. Git >= 2.23 is required." >&2; exit 1; }

workdir="${HARVE_HOME:-}"
if [[ -z "$workdir" ]]; then
    workdir="${XDG_CACHE_HOME:-${HOME}/.cache}/Harve"
fi

function log() {
    printf '[%(%F %T)T] %s\n' -1 "$1";
}

mkdir -p "$workdir"
venv="${workdir}/.venv"

if [[ ! -d "$workdir/.git" ]]; then
    git init -q "$workdir"
fi

if [[ ! -d "$venv" ]]; then
    log "creating virtualenv"
    python3 -m venv "$venv"
    "$venv/bin/pip" --quiet --no-input install -U pip
    "$venv/bin/pip" --quiet --no-input install PyGithub
fi

# Generate config file with remotes
log "get fork list"
"$venv/bin/python" > "$workdir/.git/config" <<EOP
#!/usr/bin/env python3
import os
import sys
from collections import defaultdict
from github import Github


REMOTE = """\
[remote "{remote}"]
    url = {url}
    fetch = +refs/heads/*:refs/remotes/{remote}/*
    fetch = +refs/pull/*/head:refs/remotes/{remote}/pr/*
"""

GROUPS = defaultdict(list)

def forks(repo):
    print(REMOTE.format(remote=repo.full_name, url=repo.ssh_url))
    GROUPS[repo.full_name[0].lower()].append(repo.full_name)
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

print("[remotes]")
for group, remotes in GROUPS.items():
    print(f"    harve-{group} = {' '.join(remotes)}")

EOP

git="git -C $workdir/.git"

jobs=$(( ($(nproc) + 1) / 2))

groups=$($git config --local --name-only --get-regexp 'remotes\.' | cut -d. -f2 | sort | xargs)

for group in $groups; do
    log "fetch group $group"
    # some repo may not be accessible, ignore errors
    $git fetch --prune --quiet --no-auto-gc --multiple --jobs="$jobs" "$group" 2>/dev/null || true
    rm -f "$workdir/.git/gc.log"
    $git gc --quiet
done;

: "${COMMIT:=4295585aff34ba9881ed7f64bce3481e3d217dcd}"
log "search commit $COMMIT"
set -x
# The search for the hash will return an error if not found. That the inverse of what we want.
$git branch --all --contains "${COMMIT}" || exit 0
exit 1
