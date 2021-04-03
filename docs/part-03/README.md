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
# Needed for calico
hostNetwork: true
EOF
```

## kube-prometheus-stack

Install `kube-prometheus-stack`
[helm chart](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
and modify the
[default values](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml):

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install --version 14.4.0 --namespace kube-prometheus-stack --create-namespace --values - kube-prometheus-stack prometheus-community/kube-prometheus-stack << EOF
defaultRules:
  rules:
    etcd: false
    kubernetesSystem: false
    kubeScheduler: false
additionalPrometheusRulesMap:
# Flux rule: https://toolkit.fluxcd.io/guides/monitoring/
  rule-name:
    groups:
    - name: GitOpsToolkit
      rules:
      - alert: ReconciliationFailure
        expr: max(gotk_reconcile_condition{status="False",type="Ready"}) by (namespace, name, kind) + on(namespace, name, kind) (max(gotk_reconcile_condition{status="Deleted"}) by (namespace, name, kind)) * 2 == 1
        for: 10m
        labels:
          severity: page
        annotations:
          summary: "{{ \$labels.kind }} {{ \$labels.namespace }}/{{ \$labels.name }} reconciliation has been failing for more than ten minutes."
alertmanager:
  config:
    global:
      slack_api_url: ${SLACK_INCOMING_WEBHOOK_URL}
    route:
      receiver: slack-notifications
      group_by: ["alertname", "job"]
    receivers:
      - name: "null"
      - name: "slack-notifications"
        slack_configs:
          - channel: "#${SLACK_CHANNEL}"
            send_resolved: True
            icon_url: "https://avatars3.githubusercontent.com/u/3380462"
            title: "{{ template \"slack.cp.title\" . }}"
            text: "{{ template \"slack.cp.text\" . }}"
            footer: "https://${CLUSTER_FQDN}"
            actions:
              - type: button
                text: "Runbook :blue_book:"
                url: "{{ (index .Alerts 0).Annotations.runbook_url }}"
              - type: button
                text: "Query :mag:"
                url: "{{ (index .Alerts 0).GeneratorURL }}"
              - type: button
                text: "Silence :no_bell:"
                url: "{{ template \"__alert_silence_link\" . }}"
    templates:
      - "/etc/alertmanager/config/cp-slack-templates.tmpl"
  templateFiles:
    cp-slack-templates.tmpl: |-
      {{ define "slack.cp.title" -}}
        [{{ .Status | toUpper -}}
        {{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{- end -}}
        ] {{ template "__alert_severity_prefix_title" . }} {{ .CommonLabels.alertname }}
      {{- end }}
      {{/* The test to display in the alert */}}
      {{ define "slack.cp.text" -}}
        {{ range .Alerts }}
            *Alert:* {{ .Annotations.message}}
            *Details:*
            {{ range .Labels.SortedPairs }} - *{{ .Name }}:* \`{{ .Value }}\`
            {{ end }}
            *-----*
          {{ end }}
      {{- end }}
      {{ define "__alert_silence_link" -}}
        {{ .ExternalURL }}/#/silences/new?filter=%7B
        {{- range .CommonLabels.SortedPairs -}}
          {{- if ne .Name "alertname" -}}
            {{- .Name }}%3D"{{- .Value -}}"%2C%20
          {{- end -}}
        {{- end -}}
          alertname%3D"{{ .CommonLabels.alertname }}"%7D
      {{- end }}
      {{ define "__alert_severity_prefix" -}}
          {{ if ne .Status "firing" -}}
          :white_check_mark:
          {{- else if eq .Labels.severity "critical" -}}
          :fire:
          {{- else if eq .Labels.severity "warning" -}}
          :warning:
          {{- else -}}
          :question:
          {{- end }}
      {{- end }}
      {{ define "__alert_severity_prefix_title" -}}
          {{ if ne .Status "firing" -}}
          :white_check_mark:
          {{- else if eq .CommonLabels.severity "critical" -}}
          :fire:
          {{- else if eq .CommonLabels.severity "warning" -}}
          :warning:
          {{- else if eq .CommonLabels.severity "info" -}}
          :information_source:
          {{- else if eq .CommonLabels.status_icon "information" -}}
          :information_source:
          {{- else -}}
          :question:
          {{- end }}
      {{- end }}
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
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - grafana.${CLUSTER_FQDN}
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - grafana.${CLUSTER_FQDN}
  plugins:
    - grafana-piechart-panel
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
      - name: Loki
        type: loki
        access: proxy
        url: http://loki.loki:3100
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
      # https://grafana.com/grafana/dashboards/7639
      istio-mesh:
        gnetId: 7639
        revision: 54
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/11829
      istio-performance:
        gnetId: 11829
        revision: 54
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/7636
      istio-service:
        gnetId: 7636
        revision: 54
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/7630
      istio-workload:
        gnetId: 7630
        revision: 54
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/7645
      istio-control-plane:
        gnetId: 7645
        revision: 54
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/11055
      velero-stats:
        gnetId: 11055
        revision: 2
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/10001
      jaeger:
        gnetId: 10001
        revision: 2
        datasource: Prometheus
      # https://grafana.com/grafana/dashboards/10880
      loki-promtail:
        gnetId: 10880
        revision: 1
        datasource: Prometheus
      # https://github.com/fluxcd/flux2/blob/main/manifests/monitoring/grafana/dashboards/cluster.json
      gitops-toolkit-control-plane:
        url: https://raw.githubusercontent.com/fluxcd/flux2/9916a5376123b4bcdc0f11999a8f8781ce5ee78c/manifests/monitoring/grafana/dashboards/control-plane.json
        datasource: Prometheus
      gitops-toolkit-cluster:
        url: https://raw.githubusercontent.com/fluxcd/flux2/344a909d19498f1f02b936882b529d84bbd460b8/manifests/monitoring/grafana/dashboards/cluster.json
        datasource: Prometheus
      kyverno-cluster-policy-report:
        gnetId: 13996
        revision: 3
        datasource: Prometheus
      kyverno-policy-report:
        gnetId: 13995
        revision: 3
        datasource: Prometheus
      kyverno-policy-reports:
        gnetId: 13968
        revision: 1
        datasource: Prometheus
  grafana.ini:
    server:
      root_url: https://grafana.${CLUSTER_FQDN}
    # Using oauth2-proxy instead of default Grafana Oauth
    auth.anonymous:
      enabled: true
      org_role: Admin
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

## loki

Install `loki`
[helm chart](https://artifacthub.io/packages/helm/grafana/loki)
and modify the
[default values](https://github.com/grafana/helm-charts/blob/main/charts/loki/values.yaml).

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install --version 2.3.0 --namespace loki --create-namespace --values - loki grafana/loki << EOF
serviceMonitor:
  enabled: true
EOF
```

Install promtail to ingest logs to loki:

Install `loki`
[helm chart](https://artifacthub.io/packages/helm/grafana/promtail)
and modify the
[default values](https://github.com/grafana/helm-charts/blob/main/charts/promtail/values.yaml).

```bash
helm install --version 3.1.0 --namespace promtail --create-namespace --values - promtail grafana/promtail << EOF
serviceMonitor:
  enabled: true
config:
  lokiAddress: http://loki-headless.loki:3100/loki/api/v1/push
EOF
```

## aws-node-termination-handler

Install [AWS Node Termination Handler](https://github.com/aws/aws-node-termination-handler)
which gracefully handle EC2 instance shutdown within Kubernetes.
This may happen when one of the K8s workers needs to be replaced by scheduling
the event: [https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/monitoring-instances-status-check_sched.html](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/monitoring-instances-status-check_sched.html)

Install `aws-node-termination-handler`
[helm chart](https://artifacthub.io/packages/helm/aws/aws-node-termination-handler)
and modify the
[default values](https://github.com/aws/aws-node-termination-handler/blob/main/config/helm/aws-node-termination-handler/values.yaml).

```bash
helm install --version 0.13.2 --namespace kube-system --create-namespace --values - aws-node-termination-handler eks/aws-node-termination-handler << EOF
enableRebalanceMonitoring: true
awsRegion: ${AWS_DEFAULT_REGION}
enableSpotInterruptionDraining: true
enableScheduledEventDraining: true
deleteLocalData: true
podMonitor:
  create: true
EOF
```

## kyverno

Install `kyverno`
[helm chart](https://artifacthub.io/packages/helm/kyverno/kyverno)
and modify the
[default values](https://github.com/kyverno/kyverno/blob/main/charts/kyverno/values.yaml).

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install --version v1.3.4 --namespace kyverno --create-namespace --values - kyverno kyverno/kyverno << EOF
hostNetwork: true
EOF
```

Install `policy-reporter`
[helm chart](https://github.com/fjogeleit/policy-reporter/tree/main/charts/policy-reporter)
and modify the
[default values](https://github.com/fjogeleit/policy-reporter/blob/main/charts/policy-reporter/values.yaml).

```bash
helm repo add policy-reporter https://fjogeleit.github.io/policy-reporter
helm install --version 0.22.0 --namespace policy-reporter --create-namespace --values - policy-reporter policy-reporter/policy-reporter << EOF
ui:
  enabled: true
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - host: policy-reporter.${CLUSTER_FQDN}
        paths: ["/"]
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - policy-reporter.${CLUSTER_FQDN}
monitoring:
  enabled: true
  namespace: default
target:
  loki:
    host: http://loki-headless.loki:3100
    minimumPriority: "info"
    skipExistingOnStartup: true
  # slack:
  #   webhook: "${SLACK_INCOMING_WEBHOOK_URL}"
  #   minimumPriority: "warning"
  #   skipExistingOnStartup: true
EOF
```

Install kyverno policies:

```bash
mkdir tmp/${CLUSTER_FQDN}/kyverno-policies
cat > "tmp/${CLUSTER_FQDN}/kyverno-policies/kustomization.yaml" << EOF
resources:
- github.com/kyverno/policies/pod-security?ref=930b579b1d81be74678045dd3d397f668d321cdf

patches:
  - patch: |-
      - op: replace
        path: /spec/validationFailureAction
        value: audit
    target:
      kind: ClusterPolicy
EOF
kustomize build "tmp/${CLUSTER_FQDN}/kyverno-policies" | kubectl apply -f -
```

Check if all policies are in place in `audit` mode:

```shell
kubectl get clusterpolicies.kyverno.io
```

Output:

```text
NAME                             BACKGROUND   ACTION
deny-privilege-escalation        true         audit
disallow-add-capabilities        true         audit
disallow-host-namespaces         true         audit
disallow-host-path               true         audit
disallow-host-ports              true         audit
disallow-privileged-containers   true         audit
disallow-selinux                 true         audit
require-default-proc-mount       true         audit
require-non-root-groups          true         audit
require-run-as-non-root          true         audit
restrict-apparmor-profiles       true         audit
restrict-seccomp                 true         audit
restrict-sysctls                 true         audit
restrict-volume-types            true         audit
```

Viewing policy report summaries

```shell
kubectl get policyreport -A
```

Output:

```text
NAMESPACE               NAME                            PASS   FAIL   WARN   ERROR   SKIP   AGE
amazon-cloudwatch       polr-ns-amazon-cloudwatch       99     6      0      0       0      3h55m
kube-prometheus-stack   polr-ns-kube-prometheus-stack   261    19     0      0       0      3h55m
loki                    polr-ns-loki                    34     1      0      0       0      3h55m
promtail                polr-ns-promtail                96     9      0      0       0      3h55m
```

Viewing policy violations:

```shell
kubectl describe policyreport -n amazon-cloudwatch polr-ns-amazon-cloudwatch | grep "Status: \+fail" -B10
```

Output:

```text
  Message:        validation error: Running as root is not allowed. The fields spec.securityContext.runAsNonRoot, spec.containers[*].securityContext.runAsNonRoot, and spec.initContainers[*].securityContext.runAsNonRoot must be `true`. Rule check-containers[0] failed at path /spec/securityContext/runAsNonRoot/. Rule check-containers[1] failed at path /spec/containers/0/securityContext/.
  Policy:         require-run-as-non-root
  Resources:
    API Version:  v1
    Kind:         Pod
    Name:         aws-cloudwatch-metrics-ft9fv
    Namespace:    amazon-cloudwatch
    UID:          8a520c22-4103-4c47-a0ce-dc0e77c7f4a8
  Rule:           check-containers
  Scored:         true
  Status:         fail
--
  Message:        validation error: Running as root is not allowed. The fields spec.securityContext.runAsNonRoot, spec.containers[*].securityContext.runAsNonRoot, and spec.initContainers[*].securityContext.runAsNonRoot must be `true`. Rule check-containers[0] failed at path /spec/securityContext/runAsNonRoot/. Rule check-containers[1] failed at path /spec/containers/0/securityContext/.
  Policy:         require-run-as-non-root
  Resources:
    API Version:  v1
    Kind:         Pod
    Name:         aws-cloudwatch-metrics-wrqmq
    Namespace:    amazon-cloudwatch
    UID:          18c08ec4-6aad-4e82-8a6a-b78ef7c79dd1
  Rule:           check-containers
  Scored:         true
  Status:         fail
--
  Message:        validation error: HostPath volumes are forbidden. The fields spec.volumes[*].hostPath must not be set. Rule host-path failed at path /spec/volumes/1/hostPath/
  Policy:         disallow-host-path
  Resources:
    API Version:  v1
    Kind:         Pod
    Name:         aws-cloudwatch-metrics-xzcl2
    Namespace:    amazon-cloudwatch
    UID:          8a1104f8-dc74-4f12-ac21-0939b73aa651
  Rule:           host-path
  Scored:         true
  Status:         fail
--
  Message:        validation error: Running as root is not allowed. The fields spec.securityContext.runAsNonRoot, spec.containers[*].securityContext.runAsNonRoot, and spec.initContainers[*].securityContext.runAsNonRoot must be `true`. Rule check-containers[0] failed at path /spec/securityContext/runAsNonRoot/. Rule check-containers[1] failed at path /spec/containers/0/securityContext/.
  Policy:         require-run-as-non-root
  Resources:
    API Version:  v1
    Kind:         Pod
    Name:         aws-cloudwatch-metrics-xzcl2
    Namespace:    amazon-cloudwatch
    UID:          8a1104f8-dc74-4f12-ac21-0939b73aa651
  Rule:           check-containers
  Scored:         true
  Status:         fail
--
  Message:        validation error: HostPath volumes are forbidden. The fields spec.volumes[*].hostPath must not be set. Rule host-path failed at path /spec/volumes/1/hostPath/
  Policy:         disallow-host-path
  Resources:
    API Version:  v1
    Kind:         Pod
    Name:         aws-cloudwatch-metrics-ft9fv
    Namespace:    amazon-cloudwatch
    UID:          8a520c22-4103-4c47-a0ce-dc0e77c7f4a8
  Rule:           host-path
  Scored:         true
  Status:         fail
--
  Message:        validation error: HostPath volumes are forbidden. The fields spec.volumes[*].hostPath must not be set. Rule host-path failed at path /spec/volumes/1/hostPath/
  Policy:         disallow-host-path
  Resources:
    API Version:  v1
    Kind:         Pod
    Name:         aws-cloudwatch-metrics-wrqmq
    Namespace:    amazon-cloudwatch
    UID:          18c08ec4-6aad-4e82-8a6a-b78ef7c79dd1
  Rule:           host-path
  Scored:         true
  Status:         fail
```

Create ClusterPolicy to check if `team_name` label is present in namespaces:

```bash
kubectl apply -f - << \EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-ns-labels
spec:
  validationFailureAction: audit
  background: true
  rules:
  - name: check-for-labels-on-namespace
    match:
      resources:
        kinds:
        - Namespace
    validate:
      message: "The label `team_name` is required."
      pattern:
        metadata:
          labels:
            team_name: "?*"
EOF
```

See the results:

```bash
kubectl get clusterpolicyreport
```

Output:

```text
NAME                  PASS   FAIL   WARN   ERROR   SKIP   AGE
clusterpolicyreport   0      9      0      0       0      129m
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

```shell
helm repo add splunk https://splunk.github.io/splunk-connect-for-kubernetes/
helm install --version 1.4.6 --namespace splunk-connect --create-namespace --values - splunk-connect splunk/splunk-connect-for-kubernetes << EOF
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

## Aqua Security Enforcer

Install `aqua-enforcer`
[helm chart](https://github.com/aquasecurity/aqua-helm/tree/5.3/enforcer)
and modify the
[default values](https://github.com/aquasecurity/aqua-helm/blob/5.3/enforcer/values.yaml).

```shell
helm repo add aqua-helm https://helm.aquasec.com
helm install --version 5.3.0 --namespace aqua --create-namespace --values - aqua aqua-helm/enforcer << EOF
multi_cluster: true
imageCredentials:
  create: true
  username: "${AQUA_REGISTRY_USERNAME}"
  password: "${AQUA_REGISTRY_PASSWORD}"
enforcerToken: "${AQUA_ENFORCER_TOKEN}"
gate:
  host: "${AQUA_GATE_HOST}"
  port: 443
EOF
```

## sysdig-agent

Install `sysdig-agent`
[helm chart](https://github.com/sysdiglabs/charts/tree/master/charts/sysdig)
and modify the
[default values](https://github.com/sysdiglabs/charts/blob/master/charts/sysdig/values.yaml).

```shell
helm repo add sysdig https://charts.sysdig.com
helm install --version 1.11.5 --namespace sysdig-agent --create-namespace --values - sysdig-agent sysdig/sysdig << EOF
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
`CloudWatchReadOnlyAccess` policy to `eksctl-kube1-nodegroup-ng01-NodeInstanceRole`
role. This should be done better using [IRSA](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-enable-IAM.html)
but this is enough for non-prod tests...

```shell
kubectl --namespace sysdig-agent apply -f https://raw.githubusercontent.com/sysdiglabs/ekscloudwatch/master/ekscloudwatch-config.yaml
kubectl --namespace sysdig-agent apply -f https://raw.githubusercontent.com/sysdiglabs/ekscloudwatch/master/deployment.yaml
```
