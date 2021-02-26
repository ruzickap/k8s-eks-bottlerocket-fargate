#!/usr/bin/env bash

set -eu

export BASE_DOMAIN="k8s.mylabs.dev"
export CLUSTER_NAME="k1"
export CLUSTER_FQDN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export LETSENCRYPT_ENVIRONMENT=${LETSENCRYPT_ENVIRONMENT:-staging}
export LETSENCRYPT_CERTIFICATE="https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x1.pem"
export MY_EMAIL="petr.ruzicka@gmail.com"
export AWS_DEFAULT_REGION="eu-central-1"
export MY_GITHUB_ORG_OAUTH_CLIENT_ID="3xxxxxxxxxxxxxxxxxx3"
export MY_GITHUB_ORG_OAUTH_CLIENT_SECRET="7xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx8"
export MY_GITHUB_ORG_NAME="ruzickap-org"
export KUBECONFIG="${PWD}/kubeconfig-test-${CLUSTER_NAME}.conf"

# Variables which are taken from AWS - needs to be created for tests
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export SYSDIG_AGENT_ACCESSKEY="test"
export SPLUNK_HOST="test"
export SPLUNK_TOKEN="test"
export SPLUNK_INDEX_NAME="test"
export RDS_DB_HOST="testdomain123.com"
export EFS_FS_ID="123"
export EFS_AP_ID="123"
export EKSCTL_IAM_SERVICE_ACCOUNTS='[{"metadata":{"name":"ebs-snapshot-controller"},"status":{"roleARN":"arn2"}},{"metadata":{"name":"ebs-csi-controller-sa"},"status":{"roleARN":"arn1"}}]'
export VAULT_KMS_KEY_ID="test"

test -d tests || ( echo -e "\n*** Run in top level of git repository\n"; exit 1 )

if [[ ! -x /usr/local/bin/kind ]]; then
  sudo curl -s -Lo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/v0.10.0/kind-$(uname | sed "s/./\L&/g" )-amd64"
  sudo chmod a+x /usr/local/bin/kind
else
  command -v kind
  kind version
fi

if [[ ! -x /usr/local/bin/helm ]]; then
  curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash -s -- --version v3.5.2
else
  command -v helm
  helm version
fi

echo "*** Remove cluster (if exists)"
kind get clusters | grep "${CLUSTER_NAME}" && kind delete cluster --name "${CLUSTER_NAME}"

echo -e "\n*** Create a new Kubernetes cluster using kind"
kind create cluster --name "${CLUSTER_NAME}" --image kindest/node:v1.18.15 --kubeconfig "${KUBECONFIG}" --quiet --config - << EOF
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
helm install --version 2.3.1 --namespace metallb --create-namespace --values - metallb bitnami/metallb << EOF
configInline:
  address-pools:
    - name: default
      protocol: layer2
      addresses:
        - 172.17.255.1-172.17.255.250
EOF

# Create namespaces
kubectl create namespace cert-manager
kubectl create namespace external-dns

# Create ServiceAccounts - they are originally created by eksctl
for SA in aws-load-balancer-controller cluster-autoscaler ebs-csi-controller; do
kubectl apply -f - << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
 name: ${SA}
 namespace: kube-system
EOF
done

for SA in cert-manager external-dns; do
kubectl apply -f - << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
 name: ${SA}
 namespace: ${SA}
EOF
done

echo -e "\n\n******************************\n*** Main tests\n******************************\n"

test -s ./demo-magic.sh || curl --silent https://raw.githubusercontent.com/paxtonhare/demo-magic/master/demo-magic.sh > demo-magic.sh
# shellcheck disable=SC1091
. ./demo-magic.sh

export TYPE_SPEED=600
export PROMPT_TIMEOUT=0
export NO_WAIT=true
export DEMO_PROMPT="${GREEN}➜ ${CYAN}$ "

# Changes to run test in kind like disable vault requests / change StorageClass / remove aws, eksctl commands ...
# shellcheck disable=SC1004
sed docs/part-{02..08}/README.md \
  -e 's/ --wait / --wait --timeout 30m /' \
  -e 's/.*aws /# &/' \
  -e 's/.*eksctl /# &/' \
  -e '/kubectl delete CSIDriver efs.csi.aws.com/d' \
  -e 's/^kubectl patch storageclass gp3/# &/' \
  -e 's/^vault /# &/ ; s/^kubectl exec -n vault vault-0/# &/ ; s/.*VAULT_ROOT_TOKEN/# &/' \
  -e "s/+ttlid a vault.\${CLUSTER_FQDN}/+ttlid a google.com/" \
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

test -d tmp && rm -rf tmp
mkdir tmp

# shellcheck disable=SC1091
source README-test.sh

kubectl get pods --all-namespaces

kind delete cluster --name "${CLUSTER_NAME}"

rm "${KUBECONFIG}" README-test.sh demo-magic.sh
rm -rf tmp
