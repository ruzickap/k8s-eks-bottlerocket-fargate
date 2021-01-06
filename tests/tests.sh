#!/usr/bin/env bash

set -eu

export BASE_DOMAIN="k8s.mylabs.dev"
export CLUSTER_NAME="k1"
export CLUSTER_FQDN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export LETSENCRYPT_ENVIRONMENT=${LETSENCRYPT_ENVIRONMENT:-staging}
export MY_EMAIL="petr.ruzicka@gmail.com"
export AWS_DEFAULT_REGION="eu-central-1"
export MY_GITHUB_ORG_OAUTH_CLIENT_ID="3xxxxxxxxxxxxxxxxxx3"
export MY_GITHUB_ORG_OAUTH_CLIENT_SECRET="7xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx8"
export MY_GITHUB_ORG_NAME="ruzickap-org"
export KUBECONFIG="${PWD}/kubeconfig-test-${CLUSTER_NAME}.conf"

test -d tests || ( echo -e "\n*** Run in top level of git repository\n"; exit 1 )

echo "*** Remove cluster (if exists)"
kind get clusters | grep "${CLUSTER_NAME}" && kind delete cluster --name "${CLUSTER_NAME}"

echo -e "\n*** Create a new Kubernetes cluster using kind"
kind create cluster --name "${CLUSTER_NAME}" --image kindest/node:v1.19.1 --kubeconfig "${KUBECONFIG}" --quiet --config - << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
 - role: control-plane
 - role: worker
EOF

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
helm repo add bitnami https://charts.bitnami.com/bitnami
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

# Variables which are taken from AWS - needs to be created for tests
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export ROUTE53_ROLE_ARN_CERT_MANAGER="test_arn"
export ROUTE53_ROLE_ARN_EXTERNAL_DNS="test_arn"
export RDS_DB_HOST="testdomain123.com"
export EFS_FS_ID="123"
export EFS_AP_ID="123"
export EKSCTL_IAM_SERVICE_ACCOUNTS='{"iam":{"serviceAccounts":[{"metadata":{"name":"ebs-snapshot-controller"},"status":{"roleARN":"arn2"}},{"metadata":{"name":"ebs-csi-controller-sa"},"status":{"roleARN":"arn1"}}]}}'
export KMS_KEY_ID="test"

# Changes to run test in kind like disable vault requests / change StorageClass / remove aws, eksctl commands ...
# shellcheck disable=SC1004
sed docs/part-0{2..4}/README.md \
  -e 's/.*aws /# &/' \
  -e 's/.*eksctl /# &/' \
  -e '/kubectl delete CSIDriver efs.csi.aws.com/d' \
  -e 's/^kubectl patch storageclass gp3/# &/' \
  -e 's/^vault /# &/ ; s/^kubectl exec -n vault vault-0/# &/ ; s/.*VAULT_ROOT_TOKEN/# &/' \
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
> README-test.sh

test -d tmp || mkdir -v tmp

# shellcheck disable=SC1091
source README-test.sh

kubectl get pods --all-namespaces

kind delete cluster --name "${CLUSTER_NAME}"

rm "${KUBECONFIG}" README-test.sh demo-magic.sh
rm -rf tmp
