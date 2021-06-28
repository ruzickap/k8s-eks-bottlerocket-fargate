#!/usr/bin/env bash

set -euo pipefail

export BASE_DOMAIN="k8s.mylabs.dev"
export CLUSTER_NAME="kube1-test"
export CLUSTER_FQDN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export LETSENCRYPT_ENVIRONMENT=${LETSENCRYPT_ENVIRONMENT:-staging}
export LETSENCRYPT_CERTIFICATE="https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x1.pem"
export MY_EMAIL="petr.ruzicka@gmail.com"
export AWS_DEFAULT_REGION="eu-west-1"
declare -A MY_GITHUB_ORG_OAUTH_DEX_CLIENT_ID MY_GITHUB_ORG_OAUTH_DEX_CLIENT_SECRET MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_ID MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_SECRET
MY_GITHUB_ORG_OAUTH_DEX_CLIENT_ID[${CLUSTER_NAME}]="3xxxxxxxxxxxxxxxxxx3"
MY_GITHUB_ORG_OAUTH_DEX_CLIENT_SECRET[${CLUSTER_NAME}]="7xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx8"
MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_ID[${CLUSTER_NAME}]="4xxxxxxxxxxxxxxxxxx4"
MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_SECRET[${CLUSTER_NAME}]="7xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxa"
export MY_GITHUB_ORG_OAUTH_DEX_CLIENT_ID MY_GITHUB_ORG_OAUTH_DEX_CLIENT_SECRET MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_ID MY_GITHUB_ORG_OAUTH_KEYCLOAK_CLIENT_SECRET
export MY_GITHUB_ORG_NAME="ruzickap-org"
export KUBECONFIG="${PWD}/kubeconfig-test-${CLUSTER_NAME}.conf"

export MY_PASSWORD="passwd"
export MYUSER1_ROLE_ARN="test"
export MYUSER2_ROLE_ARN="test"
export MYUSER1_USER_ACCESSKEYMYUSER="test"
export MYUSER2_USER_ACCESSKEYMYUSER="test"
export MYUSER1_USER_SECRETACCESSKEY="test"
export MYUSER2_USER_SECRETACCESSKEY="test"
export AQUA_ENFORCER_TOKEN="token"
export AQUA_REGISTRY_PASSWORD="passwd"
export AQUA_REGISTRY_USERNAME="user"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export EFS_FS_ID_DRUPAL="123"
export EFS_AP_ID_DRUPAL1="123"
export EFS_AP_ID_DRUPAL2="123"
export EFS_FS_ID_MYUSER1="123"
export EFS_AP_ID_MYUSER1="123"
export EFS_FS_ID_MYUSER2="123"
export EFS_AP_ID_MYUSER2="123"
export EKSCTL_IAM_SERVICE_ACCOUNTS='[{"metadata":{"name":"ebs-snapshot-controller"},"status":{"roleARN":"arn2"}},{"metadata":{"name":"ebs-csi-controller-sa"},"status":{"roleARN":"arn1"}}]'
export RDS_DB_HOST="testdomain123.com"
export SPLUNK_HOST="test"
export SPLUNK_INDEX_NAME="test"
export SPLUNK_TOKEN="test"
export SYSDIG_AGENT_ACCESSKEY="test"
export TAGS="aaa=bbb ccc=ddd"
export KMS_KEY_ID="test"
export OKTA_ISSUER="https://something.okta.com"
export OKTA_CLIENT_ID="0xxxxxxxxx7"
export OKTA_CLIENT_SECRET="1xxxxxH"
export VAULT_CERT_MANAGER_ROLE_ID="test"
export VAULT_CERT_MANAGER_SECRET_ID="test"
export SLACK_BOT_API_TOKEN="token"
export SLACK_INCOMING_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
export SLACK_CHANNEL="mylabs"
export AMP_WORKSPACE_ID="amp-workspace-id"

test -d tests || ( echo -e "\n*** Run in top level of git repository\n"; exit 1 )

if [[ ! -x /usr/local/bin/kind ]]; then
  sudo curl -s -Lo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/v0.10.0/kind-$(uname | sed "s/./\L&/g" )-amd64"
  sudo chmod a+x /usr/local/bin/kind
fi

echo "*** Remove cluster (if exists)"
kind get clusters | grep "${CLUSTER_NAME}" && kind delete cluster --name "${CLUSTER_NAME}"

echo -e "\n*** Create a new Kubernetes cluster using kind"
kind create cluster --name "${CLUSTER_NAME}" --image kindest/node:v1.19.7 --kubeconfig "${KUBECONFIG}" --quiet --config - << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
 - role: control-plane
 - role: worker
EOF

# Install calico
kubectl apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml
# Wait for calico to start
sleep 60

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

if [[ ! -x /usr/local/bin/helm ]]; then
  curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash -s -- --version v3.5.2
fi

echo -e "\n*** Install MetalLB"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm upgrade --install --version 2.3.1 --namespace metallb --create-namespace --values - metallb bitnami/metallb << EOF
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
kubectl create namespace kube-prometheus-stack
kubectl create namespace kuard
kubectl create namespace vault

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

if [[ ! -x /usr/local/bin/calicoctl ]]; then
  sudo curl -s -Lo /usr/local/bin/calicoctl https://github.com/projectcalico/calicoctl/releases/download/v3.18.1/calicoctl
  sudo chmod a+x /usr/local/bin/calicoctl
fi

echo -e "\n\n******************************\n*** Main tests\n******************************\n"

test -s /tmp/demo-magic.sh || curl --silent https://raw.githubusercontent.com/paxtonhare/demo-magic/master/demo-magic.sh > /tmp/demo-magic.sh
# shellcheck disable=SC1091
. /tmp/demo-magic.sh

export TYPE_SPEED=6000
export PROMPT_TIMEOUT=0
export NO_WAIT=true
export DEMO_PROMPT="${GREEN}➜ ${CYAN}$ "

# Changes to run test in kind like disable vault requests / change StorageClass / remove aws, eksctl commands ...
# shellcheck disable=SC1004
sed docs/part-{02..08}/README.md \
  -e "s/ --wait / --wait --timeout 30m /" \
  -e "s/.*aws /# &/" \
  -e "s/.*eksctl /# &/" \
  -e "s/.*AWS_CLOUDFORMATION_DETAILS.*/# &/" \
  -e "s/^kubectl patch storageclass gp3/# &/" \
  -e "s/vault auth list/echo github/ ; s/^vault /# &/ ; s/.*\$(vault /# &/ ; s/.*kubectl exec -n vault vault-0/# &/ ; s/.*VAULT_ROOT_TOKEN/# &/" \
  -e "s/+ttlid a \".*\${CLUSTER_FQDN}\"/+ttlid a google.com/" \
  -e "s/hostNetwork: true/# &/" \
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
> /tmp/README-test.sh

test -d "tmp/${CLUSTER_FQDN}/" && rm -rf "tmp/${CLUSTER_FQDN}/"
mkdir -vp "tmp/${CLUSTER_FQDN}"
touch tmp/${CLUSTER_FQDN}/kubeconfig-myuser1.conf

# shellcheck disable=SC1091
source /tmp/README-test.sh

kubectl get pods --all-namespaces

kind delete cluster --name "${CLUSTER_NAME}"

rm "${KUBECONFIG}" /tmp/README-test.sh /tmp/demo-magic.sh
rm -rf "tmp/${CLUSTER_FQDN}/"
