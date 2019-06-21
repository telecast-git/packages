#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2019, Erich Cernaj                                               #
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

if [ $# -gt 1 ]; then
    echo "Syntax: $(basename $0) [debian|redhat]" >&2
    exit 1
fi

# detect target
if command -v dpkg >/dev/null; then
    OPTION=${1:-debian}
elif comman/dev/null; then
    OPTION=${1:-redhat}
fi

# Prepare array of packages and command install for chosen distribution
case "${OPTION}" in
    'debian')
        export DEBIAN_FRONTEND=noninteractive
        INSTALL_CMD='apt-get -y install'
        PACKAGES=(
            'ruby-dev' 'make' 'gcc' 'libsqlite3-dev' 'libmysqlclient-dev'
            'libcurl4-openssl-dev' 'rake' 'libxml2-dev' 'libxslt1-dev'
            'patch' 'g++' 'build-essential')

        ;;
    'redhat')
        INSTALL_CMD='yum -y install'
        PACKAGES=(
          'ruby-devel' 'make' 'gcc' 'sqlite-devel' 'mysql-devel'
          'openssl-devel' 'curl-devel' 'rubygem-rake' 'libxml2-devel'
          'libxslt-devel' 'patch' 'expat-devel' 'gcc-c++' 'rpm-build')
        ;;
    *)
        echo "ERROR: Unknown target ${OPTION}" >&2
        exit 1
        ;;
esac

# Install packages
for PACKAGE in "${PACKAGES[@]}"; do
    echo "Install ${PACKAGE}"
    ${INSTALL_CMD} ${PACKAGE} >/dev/null
done

# Install Bundler
if ! command -v bundler >/dev/null; then
    echo 'Install Bundler'
    gem install bundler --version '< 2' >/dev/null
fi
