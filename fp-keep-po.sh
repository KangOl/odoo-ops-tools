#!/usr/bin/env bash
set -e -x
pushd "$(git rev-parse --show-toplevel)"

# remove empty directories
find . \( -name "*.~?~" -or -name "*.pyc" -or -name "*.pyo" -or -name "*.orig" -or -name "*.rej" \) -delete
find . -not -path './.git/*' -a -type d -empty -delete

# remove po for removed modules
for D in addons openerp/addons odoo/addons .; do
    find $D -maxdepth 1 -type d -and -not -name '.*' -exec bash -c "echo -ne '{} '; ls '{}' | wc -l" \; | awk '$NF==1 {print $1}' | xargs -rt -- git rm -rf --ignore-unmatch --
done;

# re-add deleted po(t)
git status --porcelain | grep -E "^DU .+\.pot?\$" | awk '{print $2}' | xargs -rt -- git add --

# keep merged modified po(t)
git status --porcelain | grep -E "^UU .+\.pot?\$" | awk '{print $2}' | xargs -rt -- git checkout --theirs --
git status --porcelain | grep -E "^UU .+\.pot?\$" | awk '{print $2}' | xargs -rt -- git add --
