#!/bin/bash -e

set -e

# distro code name
DISTRO=$(basename "$0")
DISTRO=${DISTRO%.*}

if [ "${DISTRO}" = 'debian9' ]; then
    CODENAME='stretch'
    GEMFILE_LOCK='Debian9'
elif [ "${DISTRO}" = 'debian10' ]; then
    CODENAME='buster'
    GEMFILE_LOCK='Debian10'
elif [ "${DISTRO}" = 'ubuntu1604' ]; then
    CODENAME='xenial'
    GEMFILE_LOCK='Ubuntu1604'
elif [ "${DISTRO}" = 'ubuntu1804' ]; then
    CODENAME='bionic'
    GEMFILE_LOCK='Ubuntu1804'
elif [ "${DISTRO}" = 'ubuntu1810' ]; then
    CODENAME='cosmic'
    GEMFILE_LOCK='Ubuntu1810'
elif [ "${DISTRO}" = 'ubuntu1904' ]; then
    CODENAME='disco'
    GEMFILE_LOCK='Ubuntu1904'
else
    echo "ERROR: Invalid target '${DISTRO}'" >&2
    exit 1
fi

###

BASE_DIR=$(readlink -f $(dirname $0))

SOURCES_DIR=$BASE_DIR/sources

BUILD_DIR=$HOME/build-${CODENAME}
PBUILD_DIR=$HOME/pbuilder/${CODENAME}_result
PACKAGES_DIR=$BASE_DIR

URL=$1
PKG_VERSION=${2:-1}
LOCAL_URL=$(readlink -f "${URL}" || :)

SOURCE=`basename $URL` # opennebula-1.9.90.tar.gz
PACKAGE=${SOURCE%.tar.gz} # opennebula-1.9.90

NAME=`echo $PACKAGE|cut -d'-' -f1` # opennebula
VERSION=`echo $PACKAGE|cut -d'-' -f2` # 1.9.90
CONTACT='OpenNebula Team <contact@opennebula.org>'

DATE_R=`date -R`

# clean $BUILD_DIR
mkdir -p $BUILD_DIR
rm -rf $BUILD_DIR/*

# download source
cd $BUILD_DIR
case $URL in
    http*)
        wget -q $URL || exit 1
        ;;
    *)
        cp "${LOCAL_URL}" . || exit 1
esac

# rename source
rename 's/(opennebula)-/$1_/' *tar.gz
rename 's/\.tar\.gz/.orig.tar.gz/' *tar.gz

# untar
tar xzf *tar.gz

# copy debian folder to source code
cd $PACKAGE
cp -r $PACKAGES_DIR/templates/$DISTRO-debian .
mv $DISTRO-debian debian

# copy xmlrpc-c, xml_parse_huge.patch and build_opennebula.sh
wget http://downloads.opennebula.org/extra/xmlrpc-c.tar.gz
cp $SOURCES_DIR/build_opennebula.sh .
cp $SOURCES_DIR/xml_parse_huge.patch .
tar czvf build_opennebula.tar.gz build_opennebula.sh xml_parse_huge.patch
rm build_opennebula.sh
rm xml_parse_huge.patch

# download other sources
shift || :
shift || :

for S in $@; do
    case $S in
        http*)
            wget -q $S || exit 1
            ;;
        *)
            cp $(readlink --canonicalize "${S}") . || exit 1
    esac
done

rm -rf $PBUILD_DIR/*

# if host uses package mirror, use this for pbuilder as well
if [ -f /etc/apt/sources.list.d/local-mirror.list ]; then
    MIRRORSITE=$(dirname `cut -d' ' -f2 /etc/apt/sources.list.d/local-mirror.list | head -1`)
    if [[ "${DISTRO}" =~ ubuntu ]]; then
        export MIRRORSITE="${MIRRORSITE}/ubuntu/"
    elif [[ "${DISTRO}" =~ debian ]]; then
        export MIRRORSITE="${MIRRORSITE}/debian/"
    fi
fi

# use APT http proxy for pbuilder
HTTP_PROXY=$(apt-config dump --format '%v' Acquire::http::proxy)
PB_HTTP_PROXY=${HTTP_PROXY:+--http-proxy "${HTTP_PROXY}"}

# prepare pbuilder environment
pbuilder-dist "${CODENAME}" amd64 create --updates-only ${PB_HTTP_PROXY}

# build Ruby gems
pbuilder-dist "${CODENAME}" amd64 execute --bindmounts /root -- \
    /root/packages/rubygems/build.sh \
    "${BUILD_DIR}/${NAME}_${VERSION}.orig.tar.gz" \
    "${PBUILD_DIR}" \
    "${GEMFILE_LOCK}"

# generate requirements for all Ruby gem packages
RUBYGEMS_REQ=''
for F in "${PBUILD_DIR}"/opennebula-rubygem-*.deb; do
    _NAME=$(dpkg-deb -f "${F}" Package)
    _VERS=$(dpkg-deb -f "${F}" Version)
    RUBYGEMS_REQ="${RUBYGEMS_REQ}${_NAME} (= ${_VERS}), "
done

# Prepare files in debian/
(
cd debian

# Process changelog
cat <<EOF > newchangelog
$NAME ($VERSION-$PKG_VERSION) unstable; urgency=low

  * Imported from http://packages.qa.debian.org/o/opennebula.html

 -- $CONTACT  $DATE_R

EOF
mv newchangelog changelog

# process control.m4
_BUILD_COMPONENTS=${BUILD_COMPONENTS^^}
m4 -D__RUBYGEMS_REQ__="${RUBYGEMS_REQ}" \
  ${_BUILD_COMPONENTS:+ -D_WITH_${_BUILD_COMPONENTS//[[:space:]]/_ -D_WITH_}_} \
  control.m4 >control
)

# create source package
debuild -S -us -uc -d --source-option=--include-binaries
#debuild -S -us -uc

# build binary packages
pbuilder-dist "${CODENAME}" amd64 build ${PB_HTTP_PROXY} ../*dsc

#################################################################################
## Build Ruby gems packages
#################################################################################
#
#set -e
#pwd
#RUBYGEMS_DIR=$HOME/packages/rubygems
#
## install dependencies
#"${RUBYGEMS_DIR}"/prepare.sh debian
#
## get Gemfile, Gemfile.lock
#tar -xvf "${BUILD_DIR}/${NAME}_${VERSION}.orig.tar.gz" \
#    -O "${NAME}-${VERSION}/share/install_gems/Gemfile" \
#    > /tmp/Gemfile
#
#tar -xvf "${BUILD_DIR}/${NAME}_${VERSION}.orig.tar.gz" \
#    -O "${NAME}-${VERSION}/share/install_gems/Ubuntu1804/Gemfile.lock" \
#    > /tmp/Gemfile.lock
#
## build packages
#"${RUBYGEMS_DIR}"/gemtopackage.rb -t deb \
#    --packager "${CONTACT}" \
#    --release "${PKG_VERSION}" \
#    -p "${PBUILD_DIR}" \
#    -g /tmp/Gemfile \
#    -l /tmp/Gemfile.lock

# build a tar.gz with the files
cd $PBUILD_DIR
mkdir source
mv *debian* *orig* *dsc source
tar cvzf $BUILD_DIR/$NAME-$VERSION-$PKG_VERSION.tar.gz \
    --owner=root --group=root  \
    --transform "s,^,$NAME-$VERSION-$PKG_VERSION/," \
    *deb source

# Copy tar to ~/tar

mkdir ~/tar
cp $BUILD_DIR/$NAME-$VERSION-$PKG_VERSION.tar.gz ~/tar
