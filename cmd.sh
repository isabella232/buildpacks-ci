#!/usr/bin/env bash

fly --target=buildpacks set-pipeline \
  --pipeline=brats \
  --config=<(ytt -f pipelines/brats.yml) \
  --load-vars-from=<(lpass show Shared-CF\ Buildpacks/concourse-private.yml \
  --notes && lpass show Shared-CF\ Buildpacks/deployments-buildpacks.yml \
    --notes && lpass show Shared-CF\ Buildpacks/buildpack-repos-private-keys.yml \
    --notes && lpass show Shared-CF\ Buildpacks/buildpack-cnb-repos-private-keys.yml \
    --notes && lpass show Shared-CF\ Buildpacks/git-repos-private-keys.yml --notes \
    && lpass show Shared-CF\ Buildpacks/git-repos-private-keys-two.yml \
    --notes && lpass show Shared-CF\ Buildpacks/git-repos-private-keys-three.yml --notes \
    && lpass show Shared-CF\ Buildpacks/buildpack-bosh-release-repos-private-keys.yml --notes \
    && lpass show Shared-CF\ Buildpacks/buildpack-bosh-release-repos-private-keys-2.yml --notes \
    && lpass show Shared-CF\ Buildpacks/buildpack-bosh-release-repos-private-keys-lts.yml --notes \
    && lpass show Shared-CF\ Buildpacks/dockerhub-cflinuxfs.yml --notes)       \
    --load-vars-from=public-config.yml
