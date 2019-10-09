#!/bin/bash -l

set -o errexit
set -o nounset
set -o pipefail

set -x

pushd binary-builder
  export BUNDLE_PATH="$(pwd)/vendor"
  export PATH="$PATH:$(pwd)/.bin"
  export BUNDLE_BIN_PATH=$(pwd)/.bin
  if [ ! -z "$RUBYGEM_MIRROR" ]; then
    gem sources --clear-all --add "${RUBYGEM_MIRROR}"
  fi
  gem install bundler --no-document --silent

  if [ ! -z "$RUBYGEM_MIRROR" ]; then
    bundle config mirror.https://rubygems.org "${RUBYGEM_MIRROR}"
  fi

  bundle install --jobs="$(nproc)" --binstubs="$(pwd)/.bin"

  if [ "${RUN_ORACLE_PHP_TESTS-false}" = "true" ]; then
    apt-get update && apt-get -y install awscli
    bundle exec rspec "spec/integration/${SPEC_TO_RUN}_spec.rb"
  else
    bundle check
    bundle exec "rspec spec/integration/${SPEC_TO_RUN}_spec.rb" --tag ~run_oracle_php_tests
  fi
popd
