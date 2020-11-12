#!/usr/bin/env bash

set -eu

export MY_DOMAIN=${MY_DOMAIN:-kube1.mylabs.dev}
export LETSENCRYPT_ENVIRONMENT=${LETSENCRYPT_ENVIRONMENT:-staging}
export MY_GOOGLE_OAUTH_CLIENT_ID="2xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx5.apps.googleusercontent.com"
export MY_GOOGLE_OAUTH_CLIENT_SECRET="OxxxxxxxxxxxxxxxxxxxxxxF"
CLUSTER_NAME=$(basename "${PWD}")
export CLUSTER_NAME
export KUBECONFIG="${PWD}/kubeconfig.conf"

test -d tests || ( echo -e "\n*** Run in top level of git repository\n"; exit 1 )

echo "*** Remove cluster (if exists)"
kind get clusters | grep "${CLUSTER_NAME}" && kind delete cluster --name "${CLUSTER_NAME}"

echo -e "\n*** Create a new Kubernetes cluster using kind"
kind create cluster --name "${CLUSTER_NAME}" --image kindest/node:v1.19.1 --kubeconfig kubeconfig.conf --quiet --config - << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
 - role: control-plane
 - role: worker
EOF

export KUBECONFIG="${PWD}/kubeconfig.conf"

echo -e "\n*** Create StorageClass called 'gp2'"
kubectl apply -f - << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF

echo -e "\n*** Install MetalLB"
helm repo add --force-update bitnami https://charts.bitnami.com/bitnami ; helm repo update > /dev/null
helm install --version 0.1.28 --namespace metallb --create-namespace --values - metallb bitnami/metallb << EOF
configInline:
  address-pools:
    - name: default
      protocol: layer2
      addresses:
        - 172.17.255.1-172.17.255.250
EOF

echo -e "\n\n******************************\n*** Main tests\n******************************\n"

test -s ./demo-magic.sh || curl --silent https://raw.githubusercontent.com/paxtonhare/demo-magic/master/demo-magic.sh > demo-magic.sh
# shellcheck disable=SC1091
. ./demo-magic.sh

export TYPE_SPEED=600
export PROMPT_TIMEOUT=0
export NO_WAIT=true
export DEMO_PROMPT="${GREEN}➜ ${CYAN}$ "

# shellcheck disable=SC1004
sed docs/part-0{2,3}/README.md \
  -e 's/^ROUTE53_ROLE_ARN.*/ROUTE53_ROLE_ARN="test_arn"/' \
  -e '/^# Create ClusterIssuer for production/i \
apiVersion: cert-manager.io/v1 \
kind: ClusterIssuer \
metadata: \
  name: selfsigned \
  namespace: cert-manager \
spec: \
  selfSigned: {} \
---' \
  -e "s/letsencrypt-\${LETSENCRYPT_ENVIRONMENT}-dns/selfsigned/" \
| \
sed -n "/^\`\`\`bash.*/,/^\`\`\`$/p" \
| \
sed \
  -e 's/^```bash.*/\npe '"'"'/' \
  -e 's/^```$/'"'"'/' \
> README.sh

# shellcheck disable=SC1091
source README.sh

rm demo-magic.sh

kind delete cluster --name "${CLUSTER_NAME}"

rm kubeconfig.conf
