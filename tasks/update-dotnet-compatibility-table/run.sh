#!/usr/bin/env bash

set -euo pipefail

cp -r buildpack/. artifacts

buildpack_toml="$(cat "$PWD/buildpack/buildpack.toml")"
sdk_version="$(cat "$PWD/source/data.json" | jq -r .version.ref)"
output_dir="$PWD/artifacts"
runtime_version="$(cat "$PWD/source/runtime_version")"

export GOPATH="$PWD/go"

pushd "$GOPATH/src/github.com/cloudfoundry/buildpacks-ci/tasks/update-dotnet-compatibility-table" > /dev/null
  go run . \
    --buildpack-toml "$buildpack_toml" \
    --sdk-version "$sdk_version" \
    --output-dir "$output_dir"\
    --runtime-version "$runtime_version"
popd > /dev/null
