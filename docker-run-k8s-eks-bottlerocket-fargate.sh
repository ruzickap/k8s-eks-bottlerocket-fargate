#!/usr/bin/env bash

set -euxo pipefail

docker run -it --rm \
  -e SSH_AUTH_SOCK \
  -v "${SSH_AUTH_SOCK}:${SSH_AUTH_SOCK}" \
  -v "${HOME}/.ssh:/root/.ssh:ro" \
  -v "${HOME}/Documents/secrets/secret_variables:/root/Documents/secrets/secret_variables" \
  -v "${PWD}:/mnt" \
  -w /mnt \
  ubuntu bash -eu -c " \
    apt-get update -qq && apt-get install -qq -y curl git pv > /dev/null ;\
    source run-k8s-eks-bottlerocket-fargate.sh ;\
  "
