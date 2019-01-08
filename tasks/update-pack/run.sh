#!/bin/bash -l

set -o errexit
set -o nounset
set -o pipefail

NEW_PACK_VERSION=$(cat pack/version)
sed "s/PACK_VERSION=\".*\"/PACK_VERSION=\"$NEW_PACK_VERSION\"/g" -i buildpack/scripts/install_tools.sh
rsync -a buildpack/ updated-buildpack/

pushd updated-buildpack
    # TODO : git set author
    # git add
    # git commit with message
popd