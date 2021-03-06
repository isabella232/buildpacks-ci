#!/bin/bash -l

set -o errexit
set -o nounset
set -o pipefail

set -x

SUFFIX="${STACKS_SUFFIX-}"

#shellcheck source=../../scripts/start-docker
source ./buildpacks-ci/scripts/start-docker
util::docker::start
trap util::docker::stop EXIT

pushd cflinuxfs2
  make

  versioned_stack_filename="../cflinuxfs2-artifacts/cflinuxfs2$SUFFIX-$(cat ../version/number).tar.gz"
  mv cflinuxfs2.tar.gz "$versioned_stack_filename"

  versioned_receipt_filename="../receipt-artifacts/cflinuxfs2_receipt$SUFFIX-$(cat ../version/number)"
  echo "Rootfs SHASUM: $(sha1sum "$versioned_stack_filename" | awk '{print $1}')" > "$versioned_receipt_filename"
  echo "" >> "$versioned_receipt_filename"
  cat cflinuxfs2/cflinuxfs2_dpkg_l.out >> "$versioned_receipt_filename"

  command -v git
  TERM=xterm-color git --no-pager diff cflinuxfs2/cflinuxfs2_receipt "$versioned_receipt_filename" || true
popd
