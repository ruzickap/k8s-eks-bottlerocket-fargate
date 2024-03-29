# Monitoring and Logging

## metrics-server

Install `metrics-server`
[helm chart](https://artifacthub.io/packages/helm/bitnami/metrics-server)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/metrics-server/values.yaml):

```bash
helm repo add --force-update bitnami https://charts.bitnami.com/bitnami
helm upgrade --install --version 5.9.2 --namespace kube-system --values - metrics-server bitnami/metrics-server << EOF
apiService:
  create: true
# Needed for Calico
hostNetwork: true
EOF
```

## prometheus-adapter

Installs the Prometheus Adapter for the Custom Metrics API.
Custom metrics are used in Kubernetes by Horizontal Pod Autoscaler to scale
workloads based upon your own metric pulled from an external metrics provider
like Prometheus.
It can also replace the [metrics server](https://github.com/kubernetes-incubator/metrics-server)
on clusters that already run Prometheus and collect the appropriate metrics.

Install `prometheus-adapter`
[helm chart](https://artifacthub.io/packages/helm/prometheus-community/prometheus-adapter)
and modify the
[default values](https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-adapter/values.yaml):

```shell
helm repo add --force-update prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install --version 2.15.2 --namespace prometheus-adapter --values - prometheus-adapter prometheus-community/prometheus-adapter << EOF
# Needed for Calico
hostNetwork:
  enabled: true
EOF
```

## kube-prometheus-stack

Install `kube-prometheus-stack`
[helm chart](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
and modify the
[default values](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml):

```bash
helm repo add --force-update prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install --version 17.2.1 --namespace kube-prometheus-stack --values - kube-prometheus-stack prometheus-community/kube-prometheus-stack << EOF
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
    # https://github.com/openstack/openstack-helm-infra/blob/master/prometheus/values_overrides/kubernetes.yaml
    - name: calico.rules
      rules:
      - alert: prom_exporter_calico_unavailable
        expr: avg_over_time(up{job="kubernetes-pods",application="calico"}[5m]) == 0
        for: 10m
        labels:
          severity: warning
        annotations:
          description: Calico exporter is not collecting metrics or is not available for past 10 minutes
          title: Calico exporter is not collecting metrics or is not available
      - alert: calico_datapane_failures_high_1h
        expr: absent(felix_int_dataplane_failures) OR increase(felix_int_dataplane_failures[1h]) > 5
        labels:
          severity: page
        annotations:
          description: "Felix instance {{ \$labels.instance }} has seen {{ \$value }} dataplane failures within the last hour"
          summary: "A high number of dataplane failures within Felix are happening"
      - alert: calico_datapane_address_msg_batch_size_high_5m
        expr: absent(felix_int_dataplane_addr_msg_batch_size_sum) OR absent(felix_int_dataplane_addr_msg_batch_size_count) OR (felix_int_dataplane_addr_msg_batch_size_sum/felix_int_dataplane_addr_msg_batch_size_count) > 5
        for: 5m
        labels:
          severity: page
        annotations:
          description: "Felix instance {{ \$labels.instance }} has seen a high value of {{ \$value }} dataplane address message batch size"
          summary: "Felix address message batch size is higher"
      - alert: calico_datapane_iface_msg_batch_size_high_5m
        expr: absent(felix_int_dataplane_iface_msg_batch_size_sum) OR absent(felix_int_dataplane_iface_msg_batch_size_count) OR (felix_int_dataplane_iface_msg_batch_size_sum/felix_int_dataplane_iface_msg_batch_size_count) > 5
        for: 5m
        labels:
          severity: page
        annotations:
          description: "Felix instance {{ \$labels.instance }} has seen a high value of {{ \$value }} dataplane interface message batch size"
          summary: "Felix interface message batch size is higher"
      - alert: calico_ipset_errors_high_1h
        expr: absent(felix_ipset_errors) OR increase(felix_ipset_errors[1h]) > 5
        labels:
          severity: page
        annotations:
          description: "Felix instance {{ \$labels.instance }} has seen {{ \$value }} ipset errors within the last hour"
          summary: "A high number of ipset errors within Felix are happening"
      - alert: calico_iptable_save_errors_high_1h
        expr: absent(felix_iptables_save_errors) OR increase(felix_iptables_save_errors[1h]) > 5
        labels:
          severity: page
        annotations:
          description: "Felix instance {{ \$labels.instance }} has seen {{ \$value }} iptable save errors within the last hour"
          summary: "A high number of iptable save errors within Felix are happening"
      - alert: calico_iptable_restore_errors_high_1h
        expr: absent(felix_iptables_restore_errors) OR increase(felix_iptables_restore_errors[1h]) > 5
        labels:
          severity: page
        annotations:
          description: "Felix instance {{ \$labels.instance }} has seen {{ \$value }} iptable restore errors within the last hour"
          summary: "A high number of iptable restore errors within Felix are happening"
alertmanager:
  config:
    global:
      slack_api_url: ${SLACK_INCOMING_WEBHOOK_URL}
      smtp_smarthost: "mailhog.mailhog.svc.cluster.local:1025"
      smtp_from: "alertmanager@${CLUSTER_FQDN}"
    route:
      receiver: slack-notifications
      group_by: ["alertname", "job"]
      routes:
        - match:
            severity: warning
          continue: true
          receiver: slack-notifications
        - match:
            severity: warning
          receiver: email-notifications
    receivers:
      - name: "email-notifications"
        email_configs:
        - to: "notification@${CLUSTER_FQDN}"
          require_tls: false
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
    paths: ["/"]
    pathType: ImplementationSpecific
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - alertmanager.${CLUSTER_FQDN}
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 1Gi
# https://github.com/grafana/helm-charts/blob/main/charts/grafana/values.yaml
grafana:
  serviceAccount:
    create: false
    name: grafana
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - grafana.${CLUSTER_FQDN}
    paths: ["/"]
    pathType: ImplementationSpecific
    tls:
      - secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
        hosts:
          - grafana.${CLUSTER_FQDN}
  plugins:
    - digiapulssi-breadcrumb-panel
    - grafana-piechart-panel
    # Needed for MySQL Instances Overview -> Table Openings details
    - grafana-polystat-panel
  env:
    GF_AUTH_SIGV4_AUTH_ENABLED: true
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
      - name: Loki
        type: loki
        access: proxy
        url: http://loki.loki:3100
      - name: CloudWatch
        type: cloudwatch
        jsonData:
          defaultRegion: ${AWS_DEFAULT_REGION}
      # Automated AMP provisioning as datasource does not work - needs to be done manually
      - name: Amazon Managed Prometheus
        type: prometheus
        url: https://aps-workspaces.${AWS_DEFAULT_REGION}.amazonaws.com/workspaces/${AMP_WORKSPACE_ID}
        jsonData:
          sigV4Auth: true
          sigV4Region: ${AWS_DEFAULT_REGION}
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
      k8s-cluster-summary:
        gnetId: 8685
        revision: 1
        datasource: Prometheus
      node-exporter-full:
        gnetId: 1860
        revision: 21
        datasource: Prometheus
      prometheus-2-0-overview:
        gnetId: 3662
        revision: 2
        datasource: Prometheus
      stians-disk-graphs:
        gnetId: 9852
        revision: 1
        datasource: Prometheus
      kubernetes-apiserver:
        gnetId: 12006
        revision: 1
        datasource: Prometheus
      ingress-nginx:
        gnetId: 9614
        revision: 1
        datasource: Prometheus
      ingress-nginx2:
        gnetId: 11875
        revision: 1
        datasource: Prometheus
      istio-mesh:
        gnetId: 7639
        revision: 54
        datasource: Prometheus
      istio-performance:
        gnetId: 11829
        revision: 54
        datasource: Prometheus
      istio-service:
        gnetId: 7636
        revision: 54
        datasource: Prometheus
      istio-workload:
        gnetId: 7630
        revision: 54
        datasource: Prometheus
      istio-control-plane:
        gnetId: 7645
        revision: 54
        datasource: Prometheus
      velero-stats:
        gnetId: 11055
        revision: 2
        datasource: Prometheus
      jaeger:
        gnetId: 10001
        revision: 2
        datasource: Prometheus
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
      calico-felix-dashboard:
        gnetId: 12175
        revision: 5
        datasource: Prometheus
      harbor:
        gnetId: 14075
        revision: 2
        datasource: Prometheus
      aws-efs:
        gnetId: 653
        revision: 4
        datasource: CloudWatch
      amazon-rds-os-metrics:
        gnetId: 702
        revision: 1
        datasource: CloudWatch
      aws-rds:
        gnetId: 707
        revision: 5
        datasource: CloudWatch
      aws-rds-opt:
        gnetId: 11698
        revision: 1
        datasource: CloudWatch
      aws-ec2:
        gnetId: 617
        revision: 4
        datasource: CloudWatch
      aws-network-load-balancer:
        gnetId: 12111
        revision: 2
        datasource: CloudWatch
      aws-ebs:
        gnetId: 623
        revision: 4
        datasource: CloudWatch
      CPU_Utilization_Details:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/CPU_Utilization_Details.json
        datasource: Prometheus
      Disk_Details:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/Disk_Details.json
        datasource: Prometheus
      Memory_Details:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/Memory_Details.json
        datasource: Prometheus
      MySQL_Command_Handler_Counters_Compare:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/MySQL_Command_Handler_Counters_Compare.json
        datasource: Prometheus
      MySQL_InnoDB_Compression_Details:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/MySQL_InnoDB_Compression_Details.json
        datasource: Prometheus
      MySQL_InnoDB_Details:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/MySQL_InnoDB_Details.json
        datasource: Prometheus
      MySQL_Instance_Summary:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/MySQL_Instance_Summary.json
        datasource: Prometheus
      MySQL_Instances_Compare:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/MySQL_Instances_Compare.json
        datasource: Prometheus
      MySQL_Instances_Overview:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/MySQL_Instances_Overview.json
        datasource: Prometheus
      MySQL_MyISAM_Aria_Details:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/MySQL_MyISAM_Aria_Details.json
        datasource: Prometheus
      Network_Details:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/Network_Details.json
        datasource: Prometheus
      Nodes_Compare:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/Nodes_Compare.json
        datasource: Prometheus
      Nodes_Overview:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/Nodes_Overview.json
        datasource: Prometheus
      Prometheus_Exporters_Overview:
        url: https://raw.githubusercontent.com/percona/grafana-dashboards/1316f80e834f9a3617e196b41617299c13d62421/dashboards/Prometheus_Exporters_Overview.json
        datasource: Prometheus
  grafana.ini:
    server:
      root_url: https://grafana.${CLUSTER_FQDN}
    # Using oauth2-proxy instead of default Grafana Oauth
    auth.anonymous:
      enabled: true
      org_role: Admin
  smtp:
    enabled: true
    host: "mailhog.mailhog.svc.cluster.local:1025"
    from_address: grafana@${CLUSTER_FQDN}
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
  serviceAccount:
    create: false
    name: kube-prometheus-stack-prometheus
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    paths: ["/"]
    pathType: ImplementationSpecific
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
    remoteWrite:
      - url: http://localhost:8005/workspaces/${AMP_WORKSPACE_ID}/api/v1/remote_write
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi
    containers:
      - name: aws-sigv4-proxy-sidecar
        image: public.ecr.aws/aws-observability/aws-sigv4-proxy:1.0
        args:
        - --name
        - aps
        - --region
        - ${AWS_DEFAULT_REGION}
        - --host
        - aps-workspaces.${AWS_DEFAULT_REGION}.amazonaws.com
        - --port
        - :8005
        ports:
        - name: aws-sigv4-proxy
          containerPort: 8005
EOF
```

## Enable calico monitoring

> This step should be done right after Prometheus installation to prevent
> Alertmanager from firing calico related alarms

Enable Felix Prometheus metrics:

```bash
calicoctl --allow-version-mismatch patch felixConfiguration default --patch "{\"spec\":{\"prometheusMetricsEnabled\": true}}"
```

Creating a service to expose Felix metrics according
[Monitor Calico component metrics](https://projectcalico.docs.tigera.io/maintenance/monitor/monitor-component-metrics):

```bash
kubectl apply -f - << EOF
apiVersion: v1
kind: Service
metadata:
  name: felix-metrics-svc
  namespace: kube-system
  labels:
    app: calico-felix
spec:
  selector:
    k8s-app: calico-node
  ports:
  - name: metrics-http
    port: 9091
    targetPort: 9091
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: felix-metrics-sm
  namespace: kube-system
  labels:
    app: calico
spec:
  endpoints:
  - interval: 10s
    path: /metrics
    port: metrics-http
  namespaceSelector:
    matchNames:
    - kube-system
  selector:
    matchLabels:
      app: calico-felix
EOF
```

Creating a service to expose kube-controllers metrics:

```bash
kubectl apply -f - << EOF
apiVersion: v1
kind: Service
metadata:
  name: kube-controllers-metrics-svc
  namespace: kube-system
  labels:
    app: calico-kube-controllers
spec:
  selector:
    k8s-app: calico-kube-controllers
  ports:
  - name: metrics-http
    port: 9094
    targetPort: 9094
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kube-controllers-metrics-sm
  namespace: kube-system
spec:
  endpoints:
  - interval: 10s
    path: /metrics
    port: metrics-http
  namespaceSelector:
    matchNames:
    - kube-system
  selector:
    matchLabels:
      app: calico-kube-controllers
EOF
```

## loki

Install `loki`
[helm chart](https://artifacthub.io/packages/helm/grafana/loki)
and modify the
[default values](https://github.com/grafana/helm-charts/blob/2657a57258bfcfec62a3a611209638a1ca2542ec/charts/loki/values.yaml).

```bash
helm repo add --force-update grafana https://grafana.github.io/helm-charts
helm upgrade --install --version 2.6.0 --namespace loki --create-namespace --values - loki grafana/loki << EOF
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
helm upgrade --install --version 3.7.0 --namespace promtail --create-namespace --values - promtail grafana/promtail << EOF
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
helm upgrade --install --version 0.15.2 --namespace kube-system --create-namespace --values - aws-node-termination-handler eks/aws-node-termination-handler << EOF
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
helm repo add --force-update kyverno https://kyverno.github.io/kyverno/
helm upgrade --install --version v1.4.2 --namespace kyverno --create-namespace --values - kyverno kyverno/kyverno << EOF
hostNetwork: true
EOF
```

Install `policy-reporter`
[helm chart](https://github.com/fjogeleit/policy-reporter/tree/main/charts/policy-reporter)
and modify the
[default values](https://github.com/fjogeleit/policy-reporter/blob/main/charts/policy-reporter/values.yaml).

```bash
helm repo add --force-update policy-reporter https://fjogeleit.github.io/policy-reporter
helm upgrade --install --version 1.8.6 --namespace policy-reporter --create-namespace --values - policy-reporter policy-reporter/policy-reporter << EOF
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
  slack:
    webhook: "${SLACK_INCOMING_WEBHOOK_URL}"
    minimumPriority: "warning"
    skipExistingOnStartup: true
EOF
```

Install kyverno policies:

```bash
mkdir -pv "tmp/${CLUSTER_FQDN}/kyverno-policies"
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
sleep 30
```

Check if all policies are in place in `audit` mode:

```bash
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

```bash
kubectl get policyreport -A
```

Output:

```text
NAMESPACE               NAME                            PASS   FAIL   WARN   ERROR   SKIP   AGE
amazon-cloudwatch       polr-ns-amazon-cloudwatch       39     5      0      0       0      23s
kube-prometheus-stack   polr-ns-kube-prometheus-stack   220    14     0      0       0      21s
loki                    polr-ns-loki                    37     1      0      0       0      16s
policy-reporter         polr-ns-policy-reporter         76     0      0      0       0      18s
promtail                polr-ns-promtail                38     6      0      0       0      25s
```

Viewing policy violations:

```shell
kubectl describe policyreport -n amazon-cloudwatch polr-ns-amazon-cloudwatch | grep "Status: \+fail" -B10
```

Output:

```text
  Policy:         disallow-host-path
  Resources:
    API Version:  v1
    Kind:         Pod
    Name:         aws-cloudwatch-metrics-wxzrl
    Namespace:    amazon-cloudwatch
    UID:          350f1d9e-8924-40fd-a53e-5cebf7c93e6a
  Rule:           host-path
  Scored:         true
  Severity:       medium
  Status:         fail
--
  Policy:         disallow-host-path
  Resources:
    API Version:  apps/v1
    Kind:         DaemonSet
    Name:         aws-cloudwatch-metrics
    Namespace:    amazon-cloudwatch
    UID:          436a3635-ec5a-4a35-85e8-48f0922091e0
  Rule:           autogen-host-path
  Scored:         true
  Severity:       medium
  Status:         fail
--
  Policy:         disallow-host-path
  Resources:
    API Version:  v1
    Kind:         Pod
    Name:         aws-cloudwatch-metrics-5klqf
    Namespace:    amazon-cloudwatch
    UID:          911e66b4-1e58-4f30-aff4-64f6779a06c8
  Rule:           host-path
  Scored:         true
  Severity:       medium
  Status:         fail
--
  Message:        validation error: Running as root is not allowed. The fields spec.securityContext.runAsNonRoot, spec.containers[*].securityContext.runAsNonRoot, and spec.initContainers[*].securityContext.runAsNonRoot must be `true`. Rule autogen-check-containers[0] failed at path /spec/template/spec/securityContext/runAsNonRoot/. Rule autogen-check-containers[1] failed at path /spec/template/spec/containers/0/securityContext/.
  Policy:         require-run-as-non-root
  Resources:
    API Version:  apps/v1
    Kind:         DaemonSet
    Name:         aws-cloudwatch-metrics
    Namespace:    amazon-cloudwatch
    UID:          436a3635-ec5a-4a35-85e8-48f0922091e0
  Rule:           autogen-check-containers
  Scored:         true
  Status:         fail
--
  Policy:         disallow-host-path
  Resources:
    API Version:  v1
    Kind:         Pod
    Name:         aws-cloudwatch-metrics-tm2vl
    Namespace:    amazon-cloudwatch
    UID:          17238c4c-1f90-4ac5-ab1d-6429a6e102f0
  Rule:           host-path
  Scored:         true
  Severity:       medium
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
helm repo add --force-update newrelic https://helm-charts.newrelic.com
helm upgrade --install --version 2.8.1 --namespace nri-bundle --create-namespace --values - nri-bundle newrelic/nri-bundle << EOF
prometheus:
  enabled: true
kubeEvents:
  enabled: true
logging:
  enabled: true
global:
  licenseKey: ${NEW_RELIC_LICENSE_KEY}
  cluster: ${CLUSTER_FQDN}
EOF
```

## splunk-connect

Install `splunk-connect`
[helm chart](https://github.com/splunk/splunk-connect-for-kubernetes/)
and modify the
[default values](https://github.com/splunk/splunk-connect-for-kubernetes/blob/develop/helm-chart/splunk-connect-for-kubernetes/values.yaml).

```shell
helm repo add --force-update splunk https://splunk.github.io/splunk-connect-for-kubernetes/
helm upgrade --install --version 1.4.7 --namespace splunk-connect --create-namespace --values - splunk-connect splunk/splunk-connect-for-kubernetes << EOF
global:
  splunk:
    hec:
      host: ${SPLUNK_HOST}
      token: ${SPLUNK_TOKEN}
      indexName: ${SPLUNK_INDEX_NAME}
  kubernetes:
    clusterName: ${CLUSTER_FQDN}
  prometheus_enabled: true
  monitoring_agent_enabled: true
EOF
```

## Aqua Security Enforcer

Both `aqua-enforcer` and `kube-enforcer` needs to be installed.

Install `aqua-enforcer`
[helm chart](https://github.com/aquasecurity/aqua-helm/tree/5.3/enforcer)
and modify the
[default values](https://github.com/aquasecurity/aqua-helm/blob/6.2/enforcer/values.yaml)
and [default values](https://github.com/aquasecurity/aqua-helm/blob/6.2/kube-enforcer/values.yaml).

```shell
helm repo add --force-update aqua-helm https://helm.aquasec.com
helm upgrade --install --version 6.2.5 --namespace aqua --create-namespace --values - aqua-enforcer aqua-helm/enforcer << EOF
imageCredentials:
  create: true
  username: "${AQUA_REGISTRY_USERNAME}"
  password: "${AQUA_REGISTRY_PASSWORD}"
serviceAccount:
  create: true
enforcerToken: "${AQUA_ENFORCER_TOKEN}"
enforcerLogicalName: ${USER}-test
extraEnvironmentVars:
  CLUSTER_NAME: "${USER}-test"
gate:
  host: "${AQUA_GATE_HOST}"
  port: 443
EOF

helm upgrade --install --version 6.2.4 --namespace aqua --values - kube-enforcer aqua-helm/kube-enforcer << EOF
imageCredentials:
  create: false
certsSecret:
  create: true
  # name: aqua-kube-enforcer-certs # If you're using existing certs change the name to existing secret name
  serverCertificate: LS0tL...0tLQo=
  serverKey: LS0tL...0tLQo=
aquaSecret:
  kubeEnforcerToken: ${AQUA_KUBE_ENFORCER_TOKEN}
webhooks:
  caBundle: LS...0tLQo=
envs:
  gatewayAddress: ${AQUA_GATE_HOST}:443
extraEnvironmentVars:
  CLUSTER_NAME: "${USER}-test"
EOF
```

## sysdig-agent

Install `sysdig-agent`
[helm chart](https://github.com/sysdiglabs/charts/tree/master/charts/sysdig)
and modify the
[default values](https://github.com/sysdiglabs/charts/blob/master/charts/sysdig/values.yaml).

```shell
helm repo add --force-update sysdig https://charts.sysdig.com
helm upgrade --install --version 1.11.11 --namespace sysdig-agent --create-namespace --values - sysdig-agent sysdig/sysdig << EOF
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
