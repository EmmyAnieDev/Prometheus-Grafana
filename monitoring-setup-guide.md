# EKS Monitoring with Prometheus and Grafana

This guide walks you through setting up a comprehensive monitoring solution for your EKS cluster using Prometheus and Grafana. The setup monitors your webapp, MongoDB database, and cluster infrastructure.

## Prerequisites

- EKS cluster with kubectl access configured
- Helm v3 installed
- AWS CLI configured

## Installation Guide

### 1. Create Monitoring Namespace

```bash
kubectl create namespace monitoring
```

### 2. Deploy Prometheus Stack

```bash
# Add the Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus, Grafana, Alertmanager, and exporters
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false
```

### 3. Monitor Your Web Application

Create a ServiceMonitor (`webapp-service-monitor.yaml`):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: webapp-monitor
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: webapp
  namespaceSelector:
    matchNames:
      - test-application
  endpoints:
    - port: 3000
      interval: 15s
      path: /metrics
```

Apply it:

```bash
kubectl apply -f webapp-service-monitor.yaml
```

### 4. Deploy MongoDB Monitoring

Create MongoDB exporter (`mongodb-exporter.yaml`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb-exporter
  namespace: test-application
  labels:
    app: mongodb-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mongodb-exporter
  template:
    metadata:
      labels:
        app: mongodb-exporter
    spec:
      containers:
        - name: mongodb-exporter
          image: bitnami/mongodb-exporter:0.30.0
          ports:
            - containerPort: 9216
          env:
            - name: MONGODB_URI
              value: "mongodb://$(MONGO_USER):$(MONGO_PASSWORD)@mongo-service:27017/admin"
            - name: MONGO_USER
              valueFrom:
                secretKeyRef:
                  name: mongo-secret
                  key: mongo-user
            - name: MONGO_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mongo-secret
                  key: mongo-password
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-exporter
  namespace: test-application
  labels:
    app: mongodb-exporter
spec:
  selector:
    app: mongodb-exporter
  ports:
    - port: 9216
      targetPort: 9216
```

Create MongoDB ServiceMonitor (`mongodb-service-monitor.yaml`):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb-monitor
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: mongodb-exporter
  namespaceSelector:
    matchNames:
      - test-application
  endpoints:
    - port: 9216
      interval: 15s
```

Apply both:

```bash
kubectl apply -f mongodb-exporter.yaml
kubectl apply -f mongodb-service-monitor.yaml
```

### 5. Access Grafana

```bash
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
```

Visit http://localhost:3000 with these credentials:
- Username: `admin`
- Password: `prom-operator` (default)

### 6. Set Up Grafana Dashboards

Import these recommended dashboards:
- Node Exporter Full (ID: 1860)
- Kubernetes Cluster (ID: 7249)  
- MongoDB Metrics (ID: 8588)

### 7. Add Log Collection with Loki (Optional)

#### Install Loki Stack

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=false
```

#### Check your current Loki version. If you’re using Kubernetes, run:

```bash
kubectl get pods -n <namespace> -l app=loki -o jsonpath="{.items[*].spec.containers[*].image}"
```

#### Upgrade to Loki 2.9.3

```bash
helm upgrade --install loki grafana/loki-stack --namespace monitoring --set loki.image.tag=2.9.3

# Restart Loki pods
kubectl delete pod -l app=loki -n monitoring
kubectl rollout restart deployment loki -n monitoring
kubectl rollout restart statefulset loki -n monitoring
kubectl rollout status deployment/loki -n monitoring
kubectl rollout status statefulset/loki -n monitoring
```

### Configure Grafana to use Loki as a data source:

1. In Grafana, go to Connections > Data Sources
2. Add a new Loki data source with URL: http://loki.monitoring.svc.cluster.local:3100

#### Install Promtail

```bash
helm install promtail grafana/promtail \
  --namespace monitoring \
  --set "loki.serviceName=loki"

# Update Promtail configuration
helm upgrade promtail grafana/promtail -n monitoring \
  --set "config.clients[0].url=http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"

# Restart webapp to collect logs
kubectl rollout restart deployment webapp-deployment -n test-application
```

#### Verify log collection

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail
kubectl logs -n monitoring <promtail-pod-name> | grep webapp
kubectl logs -f deployment/webapp-deployment -n test-application
```

### 8. Monitor EKS Cluster Metrics

```bash
helm install cloudwatch-exporter prometheus-community/prometheus-cloudwatch-exporter \
  --namespace monitoring \
  --set aws.region=your-region \
  --set aws.role=your-role-arn
```

### 9. Set Up Persistent Storage (Recommended for Production)

```bash
# Create storage class
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: prometheus-storage
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
reclaimPolicy: Retain
allowVolumeExpansion: true
EOF

# Update Prometheus with persistent storage
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=prometheus-storage \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=10Gi
```

## Maintenance

### Regular Updates

```bash
helm repo update
helm upgrade prometheus prometheus-community/kube-prometheus-stack --namespace monitoring
```

### Troubleshooting

- Check Prometheus targets: Forward port 9090 and visit `/targets`
- Verify ServiceMonitor configuration: `kubectl get servicemonitors -n monitoring`
- Check Prometheus logs: `kubectl logs -l app=prometheus -n monitoring`
- Verify scrape configs: 
  ```bash
  kubectl get secret prometheus-prometheus-kube-prometheus-prometheus \
    -n monitoring -o jsonpath='{.data.prometheus\.yaml}' | base64 -d
  ```

## Next Steps

- Configure alerts and notification channels in Grafana
- Create custom dashboards for application-specific metrics
- Adjust retention periods and storage based on your needs