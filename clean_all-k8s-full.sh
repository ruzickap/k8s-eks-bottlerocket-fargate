#!/usr/bin/env bash

set -eu

sed -n "/^\`\`\`bash.*/,/^\`\`\`$/p" docs/part-12/README.md | sed "/^\`\`\`*/d" | bash -eux
