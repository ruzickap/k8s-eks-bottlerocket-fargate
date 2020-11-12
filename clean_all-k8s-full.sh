#!/usr/bin/env bash

set -eu

sed -n "/^\`\`\`bash.*/,/^\`\`\`$/p" docs/part-05/README.md | sed "/^\`\`\`*/d" | bash -x
