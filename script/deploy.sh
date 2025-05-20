kubectl apply -f namespace.yaml
kubectl apply -f mongo-config.yaml
kubectl apply -f mongo-secret.yaml
kubectl apply -f mongo-deploy.yaml
kubectl apply -f webapp-deploy.yaml
