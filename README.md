# OpenNebula package builders

This repository contains scripts for building the
[OpenNebula](https://github.com/OpenNebula/one). The build process
is divided into following steps:

1. install build requirements
2. get or generate source code archive
3. build packages

## Build requirements

You need to have these packages installed on your system.

### CentOS 7

```
yum install -y rpm-build gcc-c++ libcurl-devel libxml2-devel xmlrpc-c-devel \
    openssl-devel mysql-devel sqlite-devel openssh pkgconfig ruby scons \
    sqlite-devel xmlrpc-c java-1.7.0-openjdk-devel
```

### Debian/Ubuntu

```
apt-get install -y pbuilder debhelper ubuntu-dev-tools bash-completion \
    bison default-jdk flex javahelper libxmlrpc3-client-java \
    libxmlrpc3-common-java libxml2-dev ruby scons dh-systemd
```

## Source archive

Build scripts require the source archive containing the OpenNebula source
codes, generated manual pages, and all JavaScript dependencies. The archive is available for each public
release or can be created from the source code taken from the
[VCS](https://github.com/OpenNebula/one).

### Public release archive

Inside the release download directory, you can find the source archive.
The URL template based on the desired OpenNebula version is
`https://downloads.opennebula.org/packages/opennebula-${RELEASE}/opennebula-${RELEASE}.tar.gz`

For example, the release 5.4.0 has source archive here:

* https://downloads.opennebula.org/packages/opennebula-5.4.0/opennebula-5.4.0.tar.gz

### Create archive

If you take the source code from the [VCS](https://github.com/OpenNebula/one),
you have to install all the dependencies on your own. You need to have `npm` and Ruby gem
`ronn` (https://rubygems.org/gems/ronn/) installed. We use the CentOS 7 instance to generate single archive
for all platforms.

Steps required to get sources for the OpenNebula X.Y.Z (change the placeholders with particular version) and create the archive.

```
git clone https://github.com/OpenNebula/one opennebula-X.Y.Z
cd opennebula-X.Y.Z
git checkout tags/release-X.Y.Z

# manual pages
cd share/man
./build.sh
cd ../../

# sunstone
cd  src/sunstone/public
./build.sh -d
export PATH=$PATH:$PWD/node_modules/.bin
./build.sh
rm -rf node_modules/
cd ../../../../

tar -czf opennebula-X.Y.Z.tar.gz opennebula-X.Y.Z/
```

Note: Archive name must have format `${NAME}-${RELEASE}.tar.gz`  and
main directory inside must be `${NAME}-${RELEASE}`.

## Build

There are various build scripts available, one for each supported platform.
Scripts require URL or filesystem path with the OpenNebula source archive
from the previous section.

For CentOS 7, the build must be done on the CentOS 7.

For Debian and Ubuntu, we use the single Ubuntu system to build whole package
family. Any Debian-like distribution can be used until the `pbuilder`
can bootstrap the target platform.

Examples:

```
cd packages/
./centos7.sh ../opennebula-5.4.0.tar.gz
./debian9.sh ../opennebula-5.4.0.tar.gz
./ubuntu1610.sh https://downloads.opennebula.org/packages/opennebula-5.4.0/opennebula-5.4.0.tar.gz
```

## Contact

OpenNebula web page: http://opennebula.org

Development and issue tracking: http://dev.opennebula.org

Support: http://opennebula.org/support:support

## License

Copyright 2002-2017, OpenNebula Project, OpenNebula Systems (formerly C12G Labs)

Licensed under the Apache License, Version 2.0 (the "License"); you may
not use this file except in compliance with the License. You may obtain
a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
