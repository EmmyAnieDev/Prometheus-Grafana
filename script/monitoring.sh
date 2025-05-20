kubectl apply -f webapp-service-monitor.yaml
kubectl apply -f mongodb-exporter.yaml
kubectl apply -f mongodb-service-monitor.yaml
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
