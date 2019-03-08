#!/usr/bin/env bash
set -e -x
shopt -s nullglob
pushd "$(git rev-parse --show-toplevel)"
git reset --quiet -- {{openerp/,odoo/,}addons/,}*/i18n/
find . \( -name '*.pot.orig' -o -name '*.po.orig' \) -delete
git status --porcelain -uall | awk '/\?\? .+\.pot?$/{print $2}' | xargs -r rm -f
find . -type d -name i18n -empty -delete
git checkout --quiet -- {{openerp/,odoo/,}addons/,}*/i18n/
