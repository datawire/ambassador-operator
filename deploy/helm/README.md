## Installing ambassador-operator using Helm

#### 1. Create namespace you wish to install the operator in (default: ambassador)
```
kubectl create namespace ambassador
```

#### 2. Install the operator
```
helm install ambassador-operator --namespace ambassador --set namespace=ambassador helm/ambassador-operator/
``` 
