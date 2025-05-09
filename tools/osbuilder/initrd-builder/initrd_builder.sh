#!/usr/bin/env bash
#
# Copyright (c) 2018 HyperHQ Inc.
#
# SPDX-License-Identifier: Apache-2.0

[ -z "${DEBUG}" ] || set -x

set -o errexit
# set -o nounset
set -o pipefail

script_name="${0##*/}"
script_dir="$(dirname $(readlink -f $0))"

lib_file="${script_dir}/../scripts/lib.sh"
source "$lib_file"

INITRD_IMAGE="${INITRD_IMAGE:-kata-containers-initrd.img}"
AGENT_BIN=${AGENT_BIN:-kata-agent}
AGENT_INIT=${AGENT_INIT:-no}

usage()
{
	error="${1:-0}"
	cat <<EOF
Usage: ${script_name} [options] <rootfs-dir>
	This script creates a Kata Containers initrd image file based on the
	<rootfs-dir> directory.

Options:
	-h Show help
	-o Set the path where the generated image file is stored.
	   DEFAULT: the path stored in the environment variable INITRD_IMAGE

Extra environment variables:
	AGENT_BIN:  use it to change the expected agent binary name
		    DEFAULT: kata-agent
	AGENT_INIT: use kata agent as init process
		    DEFAULT: no
EOF
exit "${error}"
}

while getopts "ho:" opt
do
	case "$opt" in
		h)	usage ;;
		o)	INITRD_IMAGE="${OPTARG}" ;;
	esac
done

shift $(( $OPTIND - 1 ))

ROOTFS="$1"


[ -n "${ROOTFS}" ] || usage
[ -d "${ROOTFS}" ] || die "${ROOTFS} is not a directory"

ROOTFS=$(readlink -f ${ROOTFS})
IMAGE_DIR=$(dirname ${INITRD_IMAGE})
IMAGE_DIR=$(readlink -f ${IMAGE_DIR})
IMAGE_NAME=$(basename ${INITRD_IMAGE})

# The kata rootfs image expects init to be installed
init="${ROOTFS}/sbin/init"
[ -x "${init}" ] || [ -L ${init} ] || die "/sbin/init is not installed in ${ROOTFS}"
OK "init is installed"
[ "${AGENT_INIT}" == "yes" ] || [ -x "${ROOTFS}/usr/bin/${AGENT_BIN}" ] || \
	die "/usr/bin/${AGENT_BIN} is not installed in ${ROOTFS}
	use AGENT_BIN env variable to change the expected agent binary name"
OK "Agent is installed"

# initramfs expects /init, create symlink only if ${ROOTFS}/init does not exist
# Init may be provided by other packages, e.g. systemd or GPU initrd/rootfs
if [ ! -x "${ROOTFS}/init" ] && [ ! -L "${ROOTFS}/init" ]; then
  # ATTN: In some instances, /init is not following two or more levels of symlinks
  # i.e. (/init to /sbin/init to /lib/systemd/systemd)
  # Setting /init directly to /lib/systemd/systemd when AGENT_INIT is disabled
  if [ "${AGENT_INIT}" = "yes" ]; then
    sudo ln -sf /sbin/init "${ROOTFS}/init"
  else
    sudo ln -sf /lib/systemd/systemd "${ROOTFS}/init"
  fi
fi

info "Creating ${IMAGE_DIR}/${IMAGE_NAME} based on rootfs at ${ROOTFS}"
( cd "${ROOTFS}" && sudo find . | sudo cpio -H newc -o | gzip -9 ) > "${IMAGE_DIR}"/"${IMAGE_NAME}"
