#!/usr/bin/env bash
set -e
ROOT=/Users/chs/devel/odoo/

if [[ $# != 3 ]]; then
  echo "Usage: $0 <source> <target> <module>"
  exit 1
fi
SRC=$1
TRG=$2
MOD=$3

set -x
pushd $ROOT/enterprise
  git checkout -q "$SRC"
popd
pushd $ROOT/odoo/stable
  git checkout -q "$SRC"
  oe-test.sh -ne "$MOD"
  git checkout -q "$TRG"
  pushd $ROOT/enterprise
    git checkout -q "$TRG"
  popd
  oe-migrate.sh -c -e -w "${DB:-test}"
popd
