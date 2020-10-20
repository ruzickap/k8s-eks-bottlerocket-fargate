# Clean-up

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg?sanitize=true
"Clean-up")

Configure `kubeconfig`:

```bash
export MY_DOMAIN=${MY_DOMAIN:-kube1.mylabs.dev}
eksctl utils write-kubeconfig --region eu-central-1 --kubeconfig kubeconfig.conf --cluster=$(echo ${MY_DOMAIN} | cut -f 1 -d .)
export KUBECONFIG=${PWD}/kubeconfig.conf}
```

Output:

```text
[ℹ]  eksctl version 0.30.0
[ℹ]  using region eu-central-1
[✔]  saved kubeconfig as "kubeconfig.conf"
```

Remove all Ingress entries and let `external-dns` to remove them...

```bash
kubectl delete ingress --kubeconfig=${PWD}/kubeconfig.conf --all --all-namespaces
```

Output:

```text
ingress.extensions "podinfo" deleted
ingress.extensions "podinfo-oauth" deleted
ingress.extensions "kube-prometheus-stack-alertmanager" deleted
ingress.extensions "kube-prometheus-stack-grafana" deleted
ingress.extensions "kube-prometheus-stack-prometheus" deleted
ingress.extensions "oauth2-proxy" deleted
```

Remove EKS cluster:

```bash
eksctl delete cluster --region eu-central-1 --name=$(echo ${MY_DOMAIN} | cut -f 1 -d .) --wait
```

Output:

```text
[ℹ]  eksctl version 0.30.0
[ℹ]  using region eu-central-1
[ℹ]  deleting EKS cluster "kube1"
[ℹ]  deleting Fargate profile "fp-default"
[ℹ]  deleted Fargate profile "fp-default"
[ℹ]  deleting Fargate profile "fp-fargate-workload"
[ℹ]  deleted Fargate profile "fp-fargate-workload"
[ℹ]  deleted 2 Fargate profile(s)
[✔]  kubeconfig has been updated
[ℹ]  cleaning up AWS load balancers created by Kubernetes objects of Kind Service or Ingress
[!]  retryable error (Throttling: Rate exceeded
[ℹ]  3 sequential tasks: { delete nodegroup "ng01", 2 sequential sub-tasks: { 3 parallel sub-tasks: { 2 sequential sub-tasks: { delete IAM role for serviceaccount "cert-manager/cert-manager", delete serviceaccount "cert-manager/cert-manager" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "external-dns/external-dns", delete serviceaccount "external-dns/external-dns" }, 2 sequential sub-tasks: { delete IAM role for serviceaccount "kube-system/aws-node", delete serviceaccount "kube-system/aws-node" } }, delete IAM OIDC provider }, delete cluster control plane "kube1" }
[ℹ]  will delete stack "eksctl-kube1-nodegroup-ng01"
[ℹ]  waiting for stack "eksctl-kube1-nodegroup-ng01" to get deleted
[!]  retryable error (Throttling: Rate exceeded
[ℹ]  will delete stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager"
[ℹ]  waiting for stack "eksctl-kube1-addon-iamserviceaccount-cert-manager-cert-manager" to get deleted
[ℹ]  will delete stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node"
[ℹ]  waiting for stack "eksctl-kube1-addon-iamserviceaccount-kube-system-aws-node" to get deleted
[ℹ]  will delete stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns"
[ℹ]  waiting for stack "eksctl-kube1-addon-iamserviceaccount-external-dns-external-dns" to get deleted
[ℹ]  deleted serviceaccount "external-dns/external-dns"
[ℹ]  deleted serviceaccount "kube-system/aws-node"
[ℹ]  deleted serviceaccount "cert-manager/cert-manager"
[ℹ]  will delete stack "eksctl-kube1-cluster"
[ℹ]  waiting for stack "eksctl-kube1-cluster" to get deleted
[✔]  all cluster resources were deleted
```

Clean Policy, User, Access Key in AWS:

```bash
# aws route53 delete-hosted-zone --id $(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${MY_DOMAIN}.\`].Id" --output text)

ROUTE53_POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName==\`${MY_DOMAIN}-AmazonRoute53Domains\`].{ARN:Arn}" --output text) && \
aws iam delete-policy --policy-arn ${ROUTE53_POLICY_ARN}
```

Cleanup + Remove Helm:

```bash
# rm -rf ~/.helm
```

Remove `tmp` directory:

```bash
rm -rf tmp
```

Remove other files:

```bash
rm demo-magic.sh kubeconfig.conf README.sh &> /dev/null
```
