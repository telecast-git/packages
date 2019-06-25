#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2002-2019, OpenNebula Project, OpenNebula Systems                #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

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
elif command -v rpm >/dev/null; then
    PKG=${1:-rpm}
fi

"${RUBYGEMS_DIR}"/gemfile2pkg \
    -t "${PKG}" \
    -p "${OUTPUT}" \
    -g "${TMP_GEMFILE}" \
    -l "${TMP_GEMFILE_LOCK}"

    #--packager "${CONTACT}" \
    #--release "${PKG_VERSION}" \

# cleanups
rm "${TMP_GEMFILE}" "${TMP_GEMFILE_LOCK}"
