# Workloads

Run some workload on the K8s...

## podinfo

Install `podinfo`
[helm chart](https://github.com/stefanprodan/podinfo/releases)
and modify the
[default values](https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml).

```bash
helm repo add --force-update sp https://stefanprodan.github.io/podinfo
helm upgrade --install --version 6.0.0 --namespace podinfo-keycloak --create-namespace --values - podinfo sp/podinfo << EOF
serviceMonitor:
  enabled: true
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy-keycloak.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy-keycloak.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hosts:
    - host: podinfo-keycloak.${CLUSTER_FQDN}
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - podinfo-keycloak.${CLUSTER_FQDN}
EOF
```

Install `podinfo` secured by `oauth2`:

```bash
helm upgrade --install --version 6.0.0 --namespace podinfo-dex --create-namespace --values - podinfo sp/podinfo << EOF
# https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml
serviceMonitor:
  enabled: true
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hosts:
    - host: podinfo-dex.${CLUSTER_FQDN}
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - podinfo-dex.${CLUSTER_FQDN}
EOF
```

Install `podinfo` and use Application Load Balancer:

```bash
helm upgrade --install --version 6.0.0 --namespace default --values - podinfo-alb sp/podinfo << EOF
ui:
  message: "Running using Application Load Balancer"
service:
  type: NodePort
serviceMonitor:
  enabled: true
ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
  hosts:
    - host: podinfo-alb.${CLUSTER_FQDN}
      paths:
        - path: /
          pathType: ImplementationSpecific
EOF
```

## Polaris

Install `polaris`
[helm chart](https://artifacthub.io/packages/helm/fairwinds-stable/polaris)
and modify the
[default values](https://github.com/FairwindsOps/charts/blob/master/stable/polaris/values.yaml).

```bash
helm repo add --force-update fairwinds-stable https://charts.fairwinds.com/stable
helm upgrade --install --version 4.0.4 --namespace polaris --create-namespace --values - polaris fairwinds-stable/polaris << EOF
dashboard:
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - polaris.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - polaris.${CLUSTER_FQDN}
EOF
```

## kubei

Kubei installation is done through the K8s manifest (not helm chart).

```bash
kubectl apply -f https://raw.githubusercontent.com/Portshift/kubei/master/deploy/kubei.yaml

kubectl apply -f - << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: kubei
  name: kubei
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    nginx.ingress.kubernetes.io/app-root: /view
spec:
  rules:
    - host: kubei.${CLUSTER_FQDN}
      http:
        paths:
        - path: /
          pathType: ImplementationSpecific
          backend:
            service:
              name: kubei
              port:
                number: 8080
  tls:
    - hosts:
        - kubei.${CLUSTER_FQDN}
      secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
EOF
```

## kube-bench

Install [kube-bench](https://github.com/aquasecurity/kube-bench) according the [https://github.com/aquasecurity/kube-bench/blob/main/docs/asff.md](https://github.com/aquasecurity/kube-bench/blob/main/docs/asff.md):

```bash
curl -s https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-eks.yaml |
  sed "s@image: .*@image: aquasec/kube-bench:latest@" |
  kubectl apply -f -
```

## kubernetes-dashboard

Install `kubernetes-dashboard`
[helm chart](https://artifacthub.io/packages/helm/k8s-dashboard/kubernetes-dashboard)
and modify the
[default values](https://github.com/kubernetes/dashboard/blob/master/charts/helm-chart/kubernetes-dashboard/values.yaml).

```bash
helm repo add --force-update kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm upgrade --install --version 4.5.0 --namespace kubernetes-dashboard --create-namespace --values - kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard << EOF
extraArgs:
  - --enable-skip-login
  - --enable-insecure-login
  - --disable-settings-authorizer
protocolHttp: true
ingress:
 enabled: true
 annotations:
   nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
   nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
 hosts:
   - kubernetes-dashboard.${CLUSTER_FQDN}
 tls:
   - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
     hosts:
       - kubernetes-dashboard.${CLUSTER_FQDN}
settings:
  clusterName: ${CLUSTER_FQDN}
  itemsPerPage: 50
metricsScraper:
  enabled: true
serviceAccount:
  name: kubernetes-dashboard-admin
EOF
```

Create `clusterrolebinding` to allow the kubernetes-dashboard to access
the K8s API:

```bash
kubectl get clusterrolebinding kubernetes-dashboard-admin &> /dev/null || kubectl create clusterrolebinding kubernetes-dashboard-admin --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:kubernetes-dashboard-admin
```

## kubeview

Install `kubeview`
[helm chart](https://artifacthub.io/packages/helm/kubeview/kubeview)
and modify the
[default values](https://github.com/benc-uk/kubeview/blob/master/charts/kubeview/values.yaml).

```bash
helm repo add --force-update kubeview https://benc-uk.github.io/kubeview/charts
helm upgrade --install --version 0.1.20 --namespace kubeview --create-namespace --values - kubeview kubeview/kubeview << EOF
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hosts:
    - host: kubeview.${CLUSTER_FQDN}
      paths: [ "/" ]
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - kubeview.${CLUSTER_FQDN}
EOF
```

## kube-ops-view

Install `kube-ops-view`
[helm chart](https://hub.kubeapps.com/charts/stable/kube-ops-view)
and modify the
[default values](https://github.com/helm/charts/blob/master/stable/kube-ops-view/values.yaml).

```bash
helm repo add --force-update stable https://charts.helm.sh/stable
helm upgrade --install --version 1.2.4 --namespace kube-ops-view --create-namespace --values - kube-ops-view stable/kube-ops-view << EOF
ingress:
  enabled: true
  hostname: kube-ops-view.${CLUSTER_FQDN}
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - kube-ops-view.${CLUSTER_FQDN}
rbac:
  create: true
EOF
```

## S3 upload test

The namespace `s3-test` and the `s3-test` service account was created by eksctl.

Test S3 access, upload and delete operations:

```bash
kubectl apply -f - << EOF
apiVersion: v1
kind: Pod
metadata:
  name: s3-test
  namespace: s3-test
spec:
  serviceAccountName: s3-test
  containers:
  - name: aws-cli
    image: amazon/aws-cli:2.4.29
    securityContext:
      runAsUser: 1000
      runAsGroup: 3000
    command:
      - /bin/bash
      - -c
      - |
        set -x
        export HOME=/tmp
        aws s3 ls --region "${AWS_DEFAULT_REGION}" "s3://${CLUSTER_FQDN}/"
        aws s3 cp --region "${AWS_DEFAULT_REGION}" /etc/hostname "s3://${CLUSTER_FQDN}/"
        aws s3 ls --region "${AWS_DEFAULT_REGION}" "s3://${CLUSTER_FQDN}/"
        aws s3 rm "s3://${CLUSTER_FQDN}/hostname"
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
  restartPolicy: Never
EOF

kubectl wait --namespace s3-test --for=condition=Ready pod s3-test && sleep 5
kubectl logs -n s3-test s3-test
kubectl delete pod -n s3-test s3-test
```

Output:

```text
pod/s3-test created
pod/s3-test condition met
+ export HOME=/tmp
+ HOME=/tmp
+ aws s3 ls --region eu-west-1 s3://kube1.k8s.mylabs.dev/
+ aws s3 cp --region eu-west-1 /etc/hostname s3://kube1.k8s.mylabs.dev/
upload: ../etc/hostname to s3://kube1.k8s.mylabs.dev/hostname
+ aws s3 ls --region eu-west-1 s3://kube1.k8s.mylabs.dev/
2021-11-29 18:01:17          8 hostname
+ aws s3 rm s3://kube1.k8s.mylabs.dev/hostname
delete: s3://kube1.k8s.mylabs.dev/hostname
pod "s3-test" deleted
```
