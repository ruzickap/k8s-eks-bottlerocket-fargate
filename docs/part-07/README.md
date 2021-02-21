# Workloads

Run some workload on the K8s...

## podinfo

Install `podinfo`
[helm chart](https://github.com/stefanprodan/podinfo/releases)
and modify the
[default values](https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml).

```bash
helm repo add sp https://stefanprodan.github.io/podinfo
helm install --version 5.1.1 --namespace default --values - podinfo sp/podinfo << EOF
serviceMonitor:
  enabled: true
ingress:
  enabled: true
  path: /
  hosts:
    - podinfo.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - podinfo.${CLUSTER_FQDN}
EOF
```

Output:

```text
"sp" has been added to your repositories
NAME: podinfo
LAST DEPLOYED: Thu Dec 10 16:02:34 2020
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  https://podinfo.k1.k8s.mylabs.dev/
```

Install `podinfo` secured by `oauth2`:

```bash
helm install --version 5.0.2 --namespace default --values - podinfo-oauth sp/podinfo << EOF
# https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml
serviceMonitor:
  enabled: true
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  path: /
  hosts:
    - podinfo-oauth.${CLUSTER_FQDN}
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - podinfo-oauth.${CLUSTER_FQDN}
EOF
```

## kuard

Install [kuard](https://github.com/kubernetes-up-and-running/kuard):

```bash
kubectl run kuard --image=gcr.io/kuar-demo/kuard-amd64:v0.10.0-green --port=8080 --expose=true --labels="app=kuard,version=v0.10.0"

kubectl apply -f - << EOF
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: kuard
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  labels:
    app: kuard
spec:
  rules:
    - host: kuard.${CLUSTER_FQDN}
      http:
        paths:
          - backend:
              serviceName: kuard
              servicePort: 8080
            path: /
  tls:
    - hosts:
        - kuard.${CLUSTER_FQDN}
      secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
EOF
```

## Polaris

Install `polaris`
[helm chart](https://artifacthub.io/packages/helm/fairwinds-stable/polaris)
and modify the
[default values](https://github.com/FairwindsOps/charts/blob/master/stable/polaris/values.yaml).

```bash
helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm install --version 1.3.1 --namespace polaris --create-namespace --values - polaris fairwinds-stable/polaris << EOF
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

Output:

```text
"fairwinds-stable" has been added to your repositories
NAME: polaris
LAST DEPLOYED: Thu Dec 10 16:02:41 2020
NAMESPACE: polaris
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
** Please be patient while the chart is being deployed **

Enjoy Polaris and smooth sailing!
To view the dashboard execute this command:

kubectl port-forward --namespace polaris svc/polaris-dashboard 8080:80

Then open http://localhost:8080 in your browser.
```

## kubei

Kubei installation is done through the K8s manifest (not helm chart).

```bash
kubectl apply -f https://raw.githubusercontent.com/Portshift/kubei/master/deploy/kubei.yaml

kubectl apply -f - << EOF
apiVersion: networking.k8s.io/v1beta1
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
          - backend:
              serviceName: kubei
              servicePort: 8080
            path: /
  tls:
    - hosts:
        - kubei.${CLUSTER_FQDN}
      secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
EOF
```

## kube-bench

Install [kube-bench](https://github.com/aquasecurity/kube-bench) according the [https://github.com/aquasecurity/kube-bench/blob/main/docs/asff.md](https://github.com/aquasecurity/kube-bench/blob/main/docs/asff.md):

```bash
curl -s https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-eks.yaml | \
  sed "s@image: .*@image: aquasec/kube-bench:latest@" | \
  kubectl apply -f -
```

## kubernetes-dashboard

Install `kubernetes-dashboard`
[helm chart](https://artifacthub.io/packages/helm/k8s-dashboard/kubernetes-dashboard)
and modify the
[default values](https://github.com/kubernetes/dashboard/blob/master/aio/deploy/helm-chart/kubernetes-dashboard/values.yaml).

```bash
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm install --version 3.0.1 --namespace kubernetes-dashboard --create-namespace --values - kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard << EOF
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

Output:

```text
"kubernetes-dashboard" has been added to your repositories
NAME: kubernetes-dashboard
LAST DEPLOYED: Thu Dec 10 16:03:04 2020
NAMESPACE: kubernetes-dashboard
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
*********************************************************************************
*** PLEASE BE PATIENT: kubernetes-dashboard may take a few minutes to install ***
*********************************************************************************
From outside the cluster, the server URL(s) are:
     http://kubernetes-dashboard.k1.k8s.mylabs.dev
```

Create `clusterrolebinding` to allow the kubernetes-dashboard to access
the K8s API:

```bash
kubectl create clusterrolebinding kubernetes-dashboard-admin --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:kubernetes-dashboard-admin
```

## Octant

```bash
helm repo add octant-dashboard https://aleveille.github.io/octant-dashboard-turnkey/repo
helm install --version 0.16.2 --namespace octant --create-namespace --values - octant octant-dashboard/octant << EOF
# https://github.com/aleveille/octant-dashboard-turnkey/blob/master/helm/values.yaml
plugins:
  install:
    - https://github.com/bloodorangeio/octant-helm/releases/download/v0.1.0/octant-helm_0.1.0_linux_amd64.tar.gz
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hosts:
    - host: octant.${CLUSTER_FQDN}
      paths: ["/"]
  tls:
    - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      hosts:
        - octant.${CLUSTER_FQDN}
EOF
```

Output:

```text
"octant-dashboard" has been added to your repositories
NAME: octant
LAST DEPLOYED: Thu Dec 10 16:03:09 2020
NAMESPACE: octant
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  https://octant.k1.k8s.mylabs.dev/
```

## kubeview

Install `kubeview`
[helm chart](https://artifacthub.io/packages/helm/kubeview/kubeview)
and modify the
[default values](https://github.com/benc-uk/kubeview/blob/master/charts/kubeview/values.yaml).

```bash
helm repo add kubeview https://benc-uk.github.io/kubeview/charts
helm install --version 0.1.17 --namespace kubeview --create-namespace --values - kubeview kubeview/kubeview << EOF
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
helm repo add stable https://charts.helm.sh/stable
helm install --version 1.2.4 --namespace kube-ops-view --create-namespace --values - kube-ops-view stable/kube-ops-view << EOF
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
