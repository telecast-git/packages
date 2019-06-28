#!/bin/bash -e

BASE_DIR=$(readlink -f $(dirname $0))

SOURCES_DIR=$BASE_DIR/sources

DISTRO=`basename ${0%.sh}`
BUILD_DIR=$HOME/build-Ubuntu-19.04
PBUILD_DIR=$HOME/pbuilder/disco_result
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

# parse and substitute values in templates
for f in `ls`; do
    for i in URL SOURCE PACKAGE NAME VERSION DATE_R CONTACT PKG_VERSION; do
        VAL=$(eval "echo \${$i}")
        if [ -f "$f" ]; then
            sed -i -e "s|%$i%|$VAL|g" $f
        fi
    done
done

# process control.m4
_BUILD_COMPONENTS=${BUILD_COMPONENTS^^}
m4 ${_BUILD_COMPONENTS:+ -D_WITH_${_BUILD_COMPONENTS//[[:space:]]/_ -D_WITH_}_} control.m4 >control
)

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

debuild -S -us -uc -d --source-option=--include-binaries
#debuild -S -us -uc

# use APT http proxy for pbuilder
HTTP_PROXY=$(apt-config dump --format '%v' Acquire::http::proxy)
PB_HTTP_PROXY=${HTTP_PROXY:+--http-proxy "${HTTP_PROXY}"}

pbuilder-dist disco amd64 create --main-only --updates-only ${PB_HTTP_PROXY}
pbuilder-dist disco amd64 build ${PB_HTTP_PROXY} ../*dsc

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
