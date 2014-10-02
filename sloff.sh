#!/bin/bash
# This script will build the Firefox binary package you downloaded
# Usage: sh sloff.sh <firefox tarball path>

# latest-firefox is 
# Copyright 2013 Ruari Oedegaard, Olso, Norway
# All rights reserved.
#
# Redistribution and use of this script, with or without modification, is
# permitted provided that the following conditions are met:
#
# 1. Redistributions of this script must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Use the architecture of the current machine or whatever the user has
# set externally

ARCH=${ARCH:-$(uname -m)}

if [ "$ARCH" = "x86_64" ]; then
	  LIBDIRSUFFIX="64"
elif [[ "$ARCH" = i?86 ]]; then
    ARCH=i686
    LIBDIRSUFFIX=""
else
    echo "The architecture $ARCH is not supported." >&2
    exit 1
fi

# Work out the latest stable Firefox if VERSION is unset
VERSION=$(basename `echo $1 | sed -nr 's|firefox-(.*)\.tar\.bz2|\1|p'`)
echo "VERSION is " $VERSION;

TMP=${TMP:-/tmp}
OUTPUT=${OUTPUT:-/tmp}
BUILD=${BUILD:-4}
TAG=${TAG:-ro}
PKGTYPE=${PKGTYPE:-tgz}
PACKAGE="$OUTPUT/mozilla-firefox-$VERSION-$ARCH-$BUILD$TAG.$PKGTYPE"

# If the package was made previously, no need to make it again. ;)
if [ -e "$PACKAGE" ]; then
  echo "$PACKAGE already exists; exiting"
  exit 0
fi

REPACKDIR=$TMP/repackage-mozilla-firefox

# Three sources are needed, here is where to find them if they are not
# already in the directory this script was started from.
FIREFOXPKG="./firefox-$VERSION.tar.bz2"
SCRIPT="${0##*/}"


# This function can be used in place of Slackware's makepkg, with the
# added bonus that it is able to make packages with root owned files
# even when run as a regular user.
makepkg() {

  # Handle Slackware's makepkg options
  while [ 0 ]; do
    if [ "$1" = "-p" -o "$1" = "--prepend" ]; then
      # option ignored, links are always prepended
      shift 1
    elif [ "$1" = "--linkadd" -o "$1" = "-l" ]; then
      if [ "$2" = "n" ]; then
        echo "\"$1 $2\" ignored, links are always converted" >&2
      fi
      shift 2
    elif [ "$1" = "--chown" -o "$1" = "-c" ]; then
      SETPERMS="$2"
      shift 2
    else
      break
    fi
  done

  # Change any symlinks into shell script code
  find * -type l -printf '( cd %h ; rm -rf %f )\n( cd %h ; ln -sf %l %f )\n' -delete > doinst.symlinks
  if grep -q . doinst.symlinks; then
    mkdir -p install
    mv doinst.symlinks install/.
  else
    rm -f doinst.symlinks
  fi

  # Prepend symlink shell script to doinst.sh
  if [ -e install/doinst.sh -a -e install/doinst.symlinks ]; then
    printf "\n" | cat - install/doinst.sh >> install/doinst.symlinks
  fi
  if [ -e install/doinst.symlinks ]; then
    mv install/doinst.symlinks install/doinst.sh
  fi

  # Reset permissions and ownership
  if [ "${SETPERMS:-y}" = "y" ]; then
    find . -type d -exec chmod 755 {} \;
    TAROWNER="--group 0 --owner 0"
  else
    TAROWNER=""
  fi

  # Create package using tar 1.13 directory formatting
  tar $TAROWNER --format=gnu --transform="s,^\./\(.\),\1," --show-stored-names -cavvf "$1" .
  echo "Slackware package $1 created."

}

# Since packaging is about to begin errors become more important now,
# so exit if things fail.
set -eu

# If the repackage is already present from the past, clear it down
# and re-create it.
if [ -d "$REPACKDIR" ]; then
  rm -fr "$REPACKDIR"
fi

mkdir -p "$REPACKDIR"/{pkg,src}

# Save a copy if this script but remove execute persmissions as it will
# later be moved into the doc directory.
install -m 644 "${0}" "$REPACKDIR/src/$SCRIPT"

# Check if the current directory contains the Firefox binary package,
# otherwise download it.
if [ -e $1 ]; then
  cp $1 "$REPACKDIR/src/"
else
  echo hell happens
  wget -P "$REPACKDIR/src" $FIREFOXPKG
fi

# Now we have all the sources in place, switch to the package directory
# and start setting things up.
cd "$REPACKDIR/pkg"

# Create the basic directory structure for files.
mkdir -p install
mkdir -p usr/bin
mkdir -p usr/doc/mozilla-firefox-$VERSION
mkdir -p usr/share/applications
mkdir -p usr/share/icons/hicolor/{16x16,32x32,48x48,128x128}/apps
mkdir -p usr/lib$LIBDIRSUFFIX/mozilla
mkdir -p usr/lib$LIBDIRSUFFIX/firefox-$VERSION

# Copy the desktop file in place

# Copy this script into the doc directory
cp ../src/$SCRIPT usr/doc/mozilla-firefox-$VERSION/$SCRIPT

# Extract the contents of the binary Firefox package into an
# appropriately named lib directory.
tar -xf ../src/firefox-$VERSION.tar.bz2 --strip 1 -C usr/lib$LIBDIRSUFFIX/firefox-$VERSION

# If present, move the readme or any other similar text files to the
# doc directory.
find usr/lib$LIBDIRSUFFIX/firefox-$VERSION -iname "*.txt" -maxdepth 1 -exec mv {} usr/doc/mozilla-firefox-$VERSION/ \;

# If a plugins folder was present move it to the mozilla lib directory.
# Otherwise just create a directory in mozilla so that there is
# definately somthing to symlink to later on in the post-install.
if [ -d usr/lib$LIBDIRSUFFIX/firefox-$VERSION/plugins ]; then
  mv usr/lib$LIBDIRSUFFIX/firefox-$VERSION/plugins usr/lib$LIBDIRSUFFIX/mozilla/
else
  mkdir usr/lib$LIBDIRSUFFIX/mozilla/plugins
fi

# Setup symlinks for firefox binary, plugin directory and icons.
(
  cd usr/bin
  ln -s ../lib$LIBDIRSUFFIX/firefox-$VERSION/firefox firefox
)
# Changes in Firefox 21 mean we need to check for the browser directory
if [ -d usr/lib$LIBDIRSUFFIX/firefox-$VERSION/browser ]; then
  (
    cd usr/lib$LIBDIRSUFFIX/firefox-$VERSION/browser
    ln -s ../../mozilla/plugins plugins
  )
else
  (
    cd usr/lib$LIBDIRSUFFIX/firefox-$VERSION
    ln -s ../mozilla/plugins plugins
  )
fi

# Changes in Firefox 21 mean we need to check for the location of icons
if /bin/ls usr/lib$LIBDIRSUFFIX/firefox-$VERSION/chrome/icons/default/default*.png >/dev/null 2>&1; then
  DEFAULTICONPATH=lib$LIBDIRSUFFIX/firefox-$VERSION/chrome/icons/default
  ALTICONPATH=lib$LIBDIRSUFFIX/firefox-$VERSION/icons
elif /bin/ls usr/lib$LIBDIRSUFFIX/firefox-$VERSION/browser/chrome/icons/default/default*.png >/dev/null 2>&1; then
  DEFAULTICONPATH=lib$LIBDIRSUFFIX/firefox-$VERSION/browser/chrome/icons/default
  ALTICONPATH=lib$LIBDIRSUFFIX/firefox-$VERSION/browser/icons
else
  echo "Changes have been made to the internal formating of the firefox source packaging!" >&2
  exit 1
fi

(
  cd usr/share/icons/hicolor/16x16/apps
  ln -s ../../../../../$DEFAULTICONPATH/default16.png firefox.png
)
(
  cd usr/share/icons/hicolor/32x32/apps
  ln -s ../../../../../$DEFAULTICONPATH/default32.png firefox.png
)
(
  cd usr/share/icons/hicolor/48x48/apps
  ln -s ../../../../../$DEFAULTICONPATH/default48.png firefox.png
)
(
  cd usr/share/icons/hicolor/128x128/apps
  ln -s ../../../../../$ALTICONPATH/mozicon128.png firefox.png
)

# Now create the post-install to register the desktop file and icons.
cat <<EOS> install/doinst.sh
# Setup menu entries
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q usr/share/applications
fi

# Setup icons
touch -c usr/share/icons/hicolor
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -tq usr/share/icons/hicolor
fi
EOS

# Create a description file inside the package.
cat <<EOD> install/slack-desc
               |-----handy-ruler------------------------------------------------------|
mozilla-firefox: mozilla-firefox (Mozilla Firefox Web browser)
mozilla-firefox:
mozilla-firefox: This project is a redesign of the Mozilla browser component written
mozilla-firefox: using the XUL user interface language. Firefox delivers safe, easy web
mozilla-firefox: browsing.
mozilla-firefox:
mozilla-firefox: Visit the Mozilla Firefox project online:
mozilla-firefox:   http://www.mozilla.org/projects/firefox/
mozilla-firefox:
mozilla-firefox:
mozilla-firefox:
EOD

# Make sure the file permissions are ok
chmod -R u+w,go+r-w,a-s .

# Create the Slackware package
makepkg --linkadd y --prepend --chown y "$PACKAGE"
