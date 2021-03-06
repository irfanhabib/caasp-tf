#!/bin/bash
#
# Author(s): Alvaro Saurin <alvaro.saurin@suse.com>
#
# Copyright (c) 2017 SUSE LINUX GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.
#
# NOTE: we assume that "images/caasp-beta.qcow2" will end up in
#       a volume named "caasp-beta.qcow2"
#
IMG_SRC="http://download.suse.de/install/SUSE-CaaSP-1.0-GMC/"
IMG_REGEX="SUSE-CaaS-Platform.*-KVM-and-Xen.*x86_64"
IMG_GLOB=$(echo "$IMG_REGEX" | sed -e 's|\.\*|\*|g')*.qcow2
IMG_LOCAL_NAME="images/beta/caasp.qcow2"
IMG_REFRESH=1

WGET="wget"

while [ $# -gt 0 ] ; do
  case $1 in
    --src|--source|-s)
      IMG_SRC=$2
      shift
      ;;
    --refresh)
      case $2 in
      False|false|FALSE|No|no|NO|0)
        echo "(disabling refresh for images)"
        IMG_REFRESH=
        ;;
      esac
      shift
      ;;
    --local|--L)
      IMG_LOCAL_NAME=$2
      shift
      ;;
    *)
      echo "Unknown argument $1"
      exit 1
      ;;
  esac
  shift
done

############################################

img_vol_name=$(basename "$IMG_LOCAL_NAME")
img_down_dir=$(dirname "$IMG_LOCAL_NAME")

images() {
  ls -1 $IMG_GLOB | sort
}

has_volume() {
  find . -name "$IMG_GLOB" &>/dev/null
}

WGET_OPTS="-r -N -c \
           --no-directories \
           --no-host-directories \
           --no-parent \
           --accept=*.qcow2 \
           --accept-regex=$IMG_REGEX"

echo ">>> Using \"$img_down_dir\" as downloads directory"
mkdir -p "$img_down_dir"
cd "$img_down_dir"

if [ -n "$IMG_REFRESH" ] || ! has_volume "$img_vol_name" ; then
  echo ">>> Downloading the latest image for importing as $img_vol_name"
  hash $WGET 2>/dev/null || { echo >&2 "FATAL: wget required. Aborting." ; exit 1 ; }
  $WGET $WGET_OPTS $IMG_SRC
  [ $? -eq 0 ] || { echo >&2 "FATAL: download failed. Aborting." ; exit 1 ; }
fi

latest_image="$(images | tail -n1 2>/dev/null)"
[ -n "$latest_image" ] || { echo >&2 "FATAL: could not determine the latest image (with glob $IMG_GLOB). Aborting." ; exit 1 ; }

echo ">>> Latest image: $img_vol_name -> $latest_image"
rm -f "$img_vol_name"
ln -sf "$latest_image" "$img_vol_name"

echo ">>> Removing previous downloads"
images | head -n -1 2>/dev/null | xargs --no-run-if-empty rm -f

echo ">>> Done!."
exit 0
