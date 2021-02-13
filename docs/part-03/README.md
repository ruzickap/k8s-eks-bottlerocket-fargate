# Monitoring and Logging

## metrics-server

Install `metrics-server`
[helm chart](https://artifacthub.io/packages/helm/bitnami/metrics-server)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/metrics-server/values.yaml):

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install --version 5.3.2 --namespace kube-system --values - metrics-server bitnami/metrics-server << EOF
apiService:
  create: true
EOF
```

## kube-prometheus-stack

Install `kube-prometheus-stack`
[helm chart](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
and modify the
[default values](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml):

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install --version 13.4.1 --namespace kube-prometheus-stack --create-namespace --values - kube-prometheus-stack prometheus-community/kube-prometheus-stack << EOF
defaultRules:
  rules:
    etcd: false
    kubernetesSystem: false
    kubeScheduler: false

alertmanager:
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - alertmanager.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - alertmanager.${CLUSTER_FQDN}
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 1Gi

# https://github.com/grafana/helm-charts/blob/main/charts/grafana/values.yaml
grafana:
  ingress:
    enabled: true
    hosts:
      - grafana.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - grafana.${CLUSTER_FQDN}
  plugins:
    - grafana-piechart-panel
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: "default"
          orgId: 1
          folder: ""
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
  dashboards:
    default:
      # https://grafana.com/grafana/dashboards/8685
      k8s-cluster-summary:
        gnetId: 8685
        revision: 1
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/1860
      node-exporter-full:
        gnetId: 1860
        revision: 21
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/3662
      prometheus-2-0-overview:
        gnetId: 3662
        revision: 2
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/9852
      stians-disk-graphs:
        gnetId: 9852
        revision: 1
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/12006
      kubernetes-apiserver:
        gnetId: 12006
        revision: 1
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/9614
      ingress-nginx:
        gnetId: 9614
        revision: 1
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/11875
      ingress-nginx2:
        gnetId: 11875
        revision: 1
        datasource: Prometheus

  grafana.ini:
    server:
      root_url: https://grafana.${CLUSTER_FQDN}
    auth.basic:
      disable_login_form: true
    auth.generic_oauth:
      name: Dex
      enabled: true
      allow_sign_up: true
      scopes: openid profile email groups
      auth_url: https://dex.${CLUSTER_FQDN}/auth
      token_url: https://dex.${CLUSTER_FQDN}/token
      api_url: https://dex.${CLUSTER_FQDN}/userinfo
      client_id: grafana.${CLUSTER_FQDN}
      client_secret: ${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}
      tls_skip_verify_insecure: true
    users:
      auto_assign_org_role: Admin

kubeControllerManager:
  enabled: false
kubeEtcd:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
prometheusOperator:
  tls:
    enabled: false
  admissionWebhooks:
    enabled: false

prometheus:
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - prometheus.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - prometheus.${CLUSTER_FQDN}
  prometheusSpec:
    externalUrl: https://prometheus.${CLUSTER_FQDN}
    ruleSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    retentionSize: 1GB
    serviceMonitorSelectorNilUsesHelmValues: false
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi
EOF
```

Output:

```text
"prometheus-community" has been added to your repositories
NAME: kube-prometheus-stack
LAST DEPLOYED: Thu Dec 10 15:56:10 2020
NAMESPACE: kube-prometheus-stack
STATUS: deployed
REVISION: 1
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace kube-prometheus-stack get pods -l "release=kube-prometheus-stack"

Visit https://github.com/prometheus-operator/kube-prometheus for instructions on how to create & configure Alertmanager and Prometheus instances using the Operator.
```

## nri-bundle

Install `nri-bundle`
[helm chart](https://artifacthub.io/packages/helm/newrelic/nri-bundle)
and modify the
[default values](https://github.com/newrelic/helm-charts/blob/master/charts/nri-bundle/values.yaml).

```shell
helm repo add newrelic https://helm-charts.newrelic.com
helm install --version 2.1.2 --namespace nri-bundle --create-namespace --values - nri-bundle newrelic/nri-bundle << EOF
prometheus:
  enabled: true
kubeEvents:
  enabled: true
logging:
  enabled: true
global:
  licenseKey: ${NEW_RELIC_LICENSE_KEY}
  cluster: ruzickap-${CLUSTER_FQDN}
EOF
```

## splunk-connect

Install `splunk-connect`
[helm chart](https://github.com/splunk/splunk-connect-for-kubernetes/)
and modify the
[default values](https://github.com/splunk/splunk-connect-for-kubernetes/blob/develop/helm-chart/splunk-connect-for-kubernetes/values.yaml).

```bash
helm repo add splunk https://splunk.github.io/splunk-connect-for-kubernetes/
helm install --version 1.4.3 --namespace splunk-connect --create-namespace --values - splunk-connect splunk/splunk-connect-for-kubernetes << EOF
global:
  splunk:
    hec:
      host: ${SPLUNK_HOST}
      token: ${SPLUNK_TOKEN}
      indexName: ${SPLUNK_INDEX_NAME}
  kubernetes:
    clusterName: ruzickap-${CLUSTER_FQDN}
  prometheus_enabled: true
  monitoring_agent_enabled: true
EOF
```

## sysdig-agent

Install `splunk-connect`
[helm chart](https://github.com/sysdiglabs/charts/tree/master/charts/sysdig)
and modify the
[default values](https://github.com/sysdiglabs/charts/blob/master/charts/sysdig/values.yaml).

```bash
helm repo add sysdig https://charts.sysdig.com
helm install --version 1.11.3 --namespace sysdig-agent --create-namespace --values - sysdig-agent sysdig/sysdig << EOF
sysdig:
  accessKey: ${SYSDIG_AGENT_ACCESSKEY}
  settings:
    collector: ingest-eu1.app.sysdig.com
    k8s_cluster_name: ${CLUSTER_FQDN}
    prometheus:
      enabled: true
      histograms: true
auditLog:
  enabled: true
EOF
```

Integrate the Kubernetes Audit facility with Sysdig Secure by enabling
CloudWatch audit logs for Sysdig [https://github.com/sysdiglabs/ekscloudwatch](https://github.com/sysdiglabs/ekscloudwatch):

As a "quick and dirty" to make `sysdig-eks-cloudwatch` running you need to add
`CloudWatchReadOnlyAccess` policy to `eksctl-k1-nodegroup-ng01-NodeInstanceRole`
role. This should be done better using [IRSA](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-enable-IAM.html)
but this is enough for non-prod tests...

```bash
kubectl --namespace sysdig-agent apply -f https://raw.githubusercontent.com/sysdiglabs/ekscloudwatch/master/ekscloudwatch-config.yaml
kubectl --namespace sysdig-agent apply -f https://raw.githubusercontent.com/sysdiglabs/ekscloudwatch/master/deployment.yaml
```
