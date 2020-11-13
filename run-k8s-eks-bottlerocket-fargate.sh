#!/usr/bin/env bash

set -eu

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
export TYPE_SPEED=600

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

### Please run these commands before running the script

# if [ -n "$SSH_AUTH_SOCK" ]; then
#  docker run -it --rm -e USER="$USER" -e MY_GOOGLE_OAUTH_CLIENT_ID -e MY_GOOGLE_OAUTH_CLIENT_SECRET -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e SSH_AUTH_SOCK -v $SSH_AUTH_SOCK:$SSH_AUTH_SOCK -v $PWD:/mnt -v $HOME/.ssh:/root/.ssh:ro ubuntu
# else
#  docker run -it --rm -e USER="$USER" -e MY_GOOGLE_OAUTH_CLIENT_ID -e MY_GOOGLE_OAUTH_CLIENT_SECRET -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -v $PWD:/mnt -v $HOME/.ssh:/root/.ssh:ro -v $HOME/.aws:/root/.aws ubuntu
# fi
# echo $(hostname -I) $(hostname) >> /etc/hosts
# apt-get update -qq && apt-get install -qq -y curl git pv > /dev/null
# cd /mnt

# export LETSENCRYPT_ENVIRONMENT="production"  # Use with care - Let's Encrypt will generate real certificates
# export MY_DOMAIN="mylabs.dev"

# ./run-k8s-eks-bottlerocket-fargate.sh

[ ! -d .git ] && git clone --quiet https://github.com/ruzickap/k8s-eks-bottlerocket-fargate && cd k8s-eks-bottlerocket-fargate

sed -n "/^\`\`\`bash.*/,/^\`\`\`$/p;/^-----$/p" docs/part-0{1..4}/README.md \
| \
sed \
  -e 's/^-----$/\np  ""\np  "################################################################################################### Press <ENTER> to continue"\nwait\n/' \
  -e 's/^```bash.*/\npe '"'"'/' \
  -e 's/^```$/'"'"'/' \
> README.sh

if [ "$#" -eq 0 ]; then
  # shellcheck disable=SC1091
  source README.sh
else
  cat README.sh
fi
