#!/bin/bash

set -e

RUBYGEMS_DIR=${RUBYGEMS_DIR:-/root/packages/rubygems/}

SOURCE=$1
OUTPUT=$2
TARGET=$3

shift 3 || :

###

"${RUBYGEMS_DIR}"/prepare.sh

# get Gemfile, Gemfile.lock
TMP_GEMFILE="$(mktemp)"
tar -xvf "${SOURCE}" \
    --wildcards --no-wildcards-match-slash \
    -O '*/share/install_gems/Gemfile' \
    > "${TMP_GEMFILE}"

TMP_GEMFILE_LOCK="$(mktemp)"
tar -xvf "${SOURCE}" \
    --wildcards --no-wildcards-match-slash \
    -O "*/share/install_gems/${TARGET}/Gemfile.lock" \
    > "${TMP_GEMFILE_LOCK}"

# detect package type
if command -v dpkg >/dev/null; then
    PKG=${1:-deb}
elif comman/dev/null; then
    PKG=${1:-rpm}
fi

"${RUBYGEMS_DIR}"/gemtopackage.rb \
    -t "${PKG}" \
    -p "${OUTPUT}" \
    -g "${TMP_GEMFILE}" \
    -l "${TMP_GEMFILE_LOCK}"

    #--packager "${CONTACT}" \
    #--release "${PKG_VERSION}" \

# cleanups
rm "${TMP_GEMFILE}" "${TMP_GEMFILE_LOCK}"
