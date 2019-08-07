#!/bin/bash

set -e -o pipefail

rm -rf ~/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
mkdir -p ~/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

cd `dirname $0`

DISTRO=`basename ${0%.sh}`
SPEC=$DISTRO.spec
BUILD_DIR=$HOME/build
RPMBUILDIR=$HOME/rpmbuild
SOURCES_DIR=$PWD/sources

URL=$1
PKG_VERSION=${2:-1}

SOURCE=`basename $URL`
PACKAGE=${SOURCE%.tar.gz}

NAME=`echo $PACKAGE|cut -d'-' -f1` # opennebula
VERSION=`echo $PACKAGE|cut -d'-' -f2` # 1.9.90
CONTACT='OpenNebula Team <contact\@opennebula.org>'

DATE=`date +"%a %b %d %Y"`

################################################################################
# Purge directories
################################################################################

rm -rf $HOME/build
rm -rf $HOME/rpmbuild
mkdir -p  $HOME/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

################################################################################
# Copy source files to SOURCE dir
################################################################################

cp templates/$DISTRO/* $RPMBUILDIR/SOURCES/

################################################################################
# Change to the SOURCES dir
################################################################################

cd $RPMBUILDIR/SOURCES


################################################################################
# Download source package to SOURCE dir
################################################################################

rm -f $SOURCE

shift || :
shift || :

for S in $URL $@; do
    case $S in
        http*)
            wget -q $S || exit 1
            ;;
        *)
            cp $(readlink --canonicalize "${S}") . || exit 1
    esac
done

################################################################################
# Copy xmlrpc-c and build_opennebula.sh sources to SOURCE dir
################################################################################

#cp $SOURCES_DIR/xmlrpc-c.tar.gz .
curl -O http://downloads.opennebula.org/extra/xmlrpc-c.tar.gz
cp $SOURCES_DIR/build_opennebula.sh .
cp $SOURCES_DIR/xml_parse_huge.patch .

################################################################################
# Substitute variables in template
################################################################################
# parse and substitute values in templates
#for f in `ls`; do
#    for i in URL SOURCE PACKAGE NAME VERSION CONTACT ETC_FILES ETC_FILES_SUNSTONE DATE PKG_VERSION; do
#        VAL=$(eval "echo \"\${$i}\"")
#        perl -p -i -e "s|%$i%|$VAL|" $SPEC
#    done
#done
#
#
#if [ -n "$MOCK" ]; then
#    exit 0
#fi

################################################################################
# Clean RPMs
################################################################################

rm -rf $HOME/rpmbuild/RPMS/x86_64/* $HOME/rpmbuild/RPMS/noarch/* $HOME/rpmbuild/SRPMS/*

# cleanup build dir
BUILD_DIR=$HOME/build
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR/src

################################################################################
# Build Ruby gems
################################################################################

MOCK_CFG='epel-7-x86_64'

# use YUM http proxy
if egrep -q 'proxy\s*=' /etc/yum.conf; then
    http_proxy=$(egrep 'proxy\s*=' /etc/yum.conf | sed -e 's/^proxy\s*=\s*//')
    export http_proxy
fi

# build Ruby gems
mock -r "${MOCK_CFG}" --init
mock -r "${MOCK_CFG}" --install yum
mock -r "${MOCK_CFG}" --enable-network \
    --enable-plugin=bind_mount \
    --plugin-option=bind_mount:dirs='[("/root", "/root")]' \
    --chroot "/root/packages/rubygems/build.sh ${RPMBUILDIR}/SOURCES/${SOURCE} ${BUILD_DIR} CentOS7"

# generate spec requirements for all Ruby gem packages
RUBYGEMS_REQ=''
while IFS= read -r LINE; do
    _NAME=$(echo "${LINE}" | cut -d' ' -f1)
    _VERSION=$(echo "${LINE}" | cut -d' ' -f2)
    _RELEASE=$(echo "${LINE}" | cut -d' ' -f3)

    RUBYGEMS_REQ="${RUBYGEMS_REQ}Requires: ${_NAME} = ${_VERSION}"$'\n'
done < <(rpm -qp "${BUILD_DIR}"/opennebula-rubygem-*.rpm --queryformat '%{NAME} %{VERSION} %{RELEASE}\n')

################################################################################
# Copy the template
################################################################################

m4 -D__VERSION__="${VERSION}" \
    -D__PKG_VERSION__="${PKG_VERSION}" \
    -D__RUBYGEMS_REQ__="${RUBYGEMS_REQ}" \
    "${DISTRO}.spec.m4" >"${SPEC}"

################################################################################
# Build the package
################################################################################

_BUILD_COMPONENTS=${BUILD_COMPONENTS,,}
_WITH_COMPONENTS=${_BUILD_COMPONENTS:+ --with ${_BUILD_COMPONENTS//[[:space:]]/ --with }}

#SRPM=$(rpmbuild -bs "${SPEC}" ${_WITH_COMPONENTS} | grep 'Wrote:' | cut -d' ' -f2)
mock -r "${MOCK_CFG}" --init

# build source package
MOCK_DIR=$(mktemp -d)
mock -r "${MOCK_CFG}" -v \
    --buildsrpm \
    --resultdir="${MOCK_DIR}" \
    --spec "${SPEC}" \
    --sources . \
    ${_WITH_COMPONENTS}

# check we have 1 source RPM
_SRPMS=$(ls "${MOCK_DIR}/"*.src.rpm)
if [ "$(echo "${_SRPMS}" | wc -l)" -ne 1 ]; then
    echo "ERROR: Expected 1 source RPM, but got:" >&2
    echo "__START__${_SRPMS}__END__" >&2
    exit 1
fi

SRPM=$(basename "${_SRPMS}")
cp "${MOCK_DIR}/${SRPM}" "${BUILD_DIR}/src/"
rm -rf "${MOCK_DIR}"

# build binary package
MOCK_DIR=$(mktemp -d)
#mock -r "${MOCK_CFG}" --installdeps "${SRPM}" ${_WITH_COMPONENTS}
mock -r "${MOCK_CFG}" -v \
    --rebuild "${BUILD_DIR}/${SRPM}" \
    --resultdir="${MOCK_DIR}" \
    ${_WITH_COMPONENTS}

##################################################################################
### Build Ruby gems packages
##################################################################################
#
#/root/packages/rubygems/build.sh \
#    "${RPMBUILDIR}/SOURCES/${SOURCE}" \
#    "${BUILD_DIR}" \
#    CentOS7
#
#set -e
#RUBYGEMS_DIR=$HOME/packages/rubygems
#
## install dependencies
#"${RUBYGEMS_DIR}"/prepare.sh redhat
#
## get Gemfile, Gemfile.lock
#tar -xvf "${RPMBUILDIR}/SOURCES/${SOURCE}" \
#    -O "${NAME}-${VERSION}/share/install_gems/Gemfile" \
#    > Gemfile
#
#tar -xvf "${RPMBUILDIR}/SOURCES/${SOURCE}" \
#    -O "${NAME}-${VERSION}/share/install_gems/CentOS7/Gemfile.lock" \
#    > Gemfile.lock
#
## build packages
#"${RUBYGEMS_DIR}"/gemtopackage.rb -t rpm \
#    --packager "${CONTACT}" \
#    --release "${PKG_VERSION}" \
#    -p "${BUILD_DIR}" \
#    -g Gemfile \
#    -l Gemfile.lock

################################################################################
# Put all the RPMs into a tar.gz
################################################################################

#BUILD_DIR=$HOME/build
#rm -rf $BUILD_DIR
#mkdir -p $BUILD_DIR/src

#cp $HOME/rpmbuild/RPMS/x86_64/* $BUILD_DIR
#cp $HOME/rpmbuild/RPMS/noarch/* $BUILD_DIR
#cp $HOME/rpmbuild/SRPMS/* $BUILD_DIR/src
cp "${MOCK_DIR}"/*.rpm "${BUILD_DIR}"
rm -rf "${MOCK_DIR}"

cd $BUILD_DIR
tar czf $NAME-$VERSION-$PKG_VERSION.tar.gz \
    --owner=root --group=root  \
    --transform "s,^,$NAME-$VERSION-$PKG_VERSION/," \
    *

################################################################################
# Move tar.gz to ~/tar
################################################################################

mkdir -p ~/tar
cp -f $NAME-$VERSION-$PKG_VERSION.tar.gz ~/tar

