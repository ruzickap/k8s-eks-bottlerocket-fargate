#!/usr/bin/env bash

set -euo pipefail

sed -n "/^\`\`\`bash.*/,/^\`\`\`$/p" docs/part-13/README.md | sed "/^\`\`\`*/d" | bash -eux
