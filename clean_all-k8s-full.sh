#!/usr/bin/env bash

set -eu

sed -n "/^\`\`\`bash.*/,/^\`\`\`$/p" docs/part-06/README.md | sed "/^\`\`\`*/d" | bash -eux
