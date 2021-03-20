#!/usr/bin/env bash

set -euo pipefail

################################################
# include the magic
################################################
test -s ./demo-magic.sh || curl --silent https://raw.githubusercontent.com/paxtonhare/demo-magic/master/demo-magic.sh > demo-magic.sh
# shellcheck disable=SC1091
. ./demo-magic.sh

################################################
# Configure the options
################################################

#
# speed at which to simulate typing. bigger num = faster
#
export TYPE_SPEED=6000

# Uncomment to run non-interactively
export PROMPT_TIMEOUT=0

# No wait
#export NO_WAIT=false
export NO_WAIT=true

#
# custom prompt
#
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
#DEMO_PROMPT="${GREEN}➜ ${CYAN}\W "
export DEMO_PROMPT="${GREEN}➜ ${CYAN}$ "

# hide the evidence
clear

sed -n "/^\`\`\`bash.*/,/^\`\`\`$/p;/^-----$/p" docs/part-{01..12}/README.md \
| \
sed \
  -e 's/^-----$/\np  ""\np  "################################################################################################### Press <ENTER> to continue"\nwait\n/' \
  -e 's/^```bash.*/\npe '"'"'/' \
  -e 's/^```$/'"'"'/' \
> README.sh

if [ "$#" -eq 0 ]; then
  # shellcheck disable=SC1090
  source "${HOME}/Documents/secrets/secret_variables"
  # shellcheck disable=SC1091
  source README.sh
else
  cat README.sh
fi
