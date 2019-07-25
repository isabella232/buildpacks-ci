#!/bin/bash -l

set -o errexit
set -o nounset
set -o pipefail

version="$(cat version/version)"

calculate_checksum() {
    osx="$1"
    wget https://github.com/cloudfoundry/stack-auditor/releases/download/v"$version"/stack-auditor-"$version"-"$osx".tgz
    local checksum="$(shasum -a 1 stack-auditor-"$version"-"$osx".tgz | cut -d " " -f 1)"
    echo "$checksum"
}






cat <<EOF > metadata.yml
- authors:
  - contact: cf-buildpacks-eng@pivotal.io
    name: Pivotal Buildpacks team
  binaries:
  - checksum: "$(calculate_checksum darwin)"
    platform: osx
    url: https://github.com/cloudfoundry/stack-auditor/releases/download/v"$version"/stack-auditor-"$version"-darwin.tgz
  - checksum: "$(calculate_checksum windows)"
    platform: win64
    url: https://github.com/cloudfoundry/stack-auditor/releases/download/v"$version"/stack-auditor-"$version"-windows.zip
  - checksum: "$(calculate_checksum linux)"
    platform: linux64
    url: https://github.com/cloudfoundry/stack-auditor/releases/download/v"$version"/stack-auditor-"$version"-linux.tgz
  company: Pivotal
  created: 2019-07-25T15:32:00Z
  description: Provides commands for listing apps and their stacks, migrating apps
    to a new stack, and deleting a stack
  homepage: https://github.com/cloudfoundry/stack-auditor
  name: stack-auditor
  updated: 2019-07-18T14:24:60Z
  version: $version

EOF