#!/bin/bash -l

set -o errexit
set -o nounset
set -o pipefail

set -x

rsync -a buildpack/ updated-buildpack/

pushd updated-buildpack/scripts
  git checkout master
popd

pushd updated-buildpack
  git add .

  set +e
    git diff --cached --exit-code
    no_changes=$?
  set -e

  if [ $no_changes -ne 0 ]
  then
    git commit -m "Update scripts"
  else
    echo "scripts are already up to date"
  fi
popd
