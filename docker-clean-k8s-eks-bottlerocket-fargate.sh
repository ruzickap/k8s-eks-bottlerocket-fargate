#!/usr/bin/env bash

set -euxo pipefail

docker run -it --rm \
  -e CLUSTER_NAME="kube2" \
  -v "${HOME}/Documents/secrets/secret_variables:/root/Documents/secrets/secret_variables" \
  -v "${PWD}:/mnt" \
  -w /mnt \
  ubuntu \
  bash -eu -c " \
    source \"\${HOME}/Documents/secrets/secret_variables\"
    sed -n '/^\`\`\`bash.*/,/^\`\`\`$/p' docs/part-13/README.md | sed '/^\`\`\`*/d' | bash -eux
  "
