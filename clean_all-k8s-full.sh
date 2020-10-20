#!/usr/bin/env bash

set -eu

sed -n "/^\`\`\`bash.*/,/^\`\`\`$/p" docs/part-04/README.md | sed "/^\`\`\`*/d" | bash -x
