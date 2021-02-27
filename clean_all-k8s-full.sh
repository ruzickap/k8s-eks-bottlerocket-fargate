#!/usr/bin/env bash

set -euo pipefail

sed -n "/^\`\`\`bash.*/,/^\`\`\`$/p" docs/part-12/README.md | sed "/^\`\`\`*/d" | bash -eux
