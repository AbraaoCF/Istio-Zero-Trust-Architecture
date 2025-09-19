# Istio Zero Trust Architecture

## Prerequisites

- Docker
- Kind (`go install sigs.k8s.io/kind@v0.30.0`)
- Kubectl (`brew install kubectl`)
- Istioctl (`brew install istioctl`)

## Steps

1) [Setup Kind](https://istio.io/latest/docs/setup/platform-setup/kind/)

    (a) Create cluster
    ```
    kind create cluster --name istio-zt-architecture
    ```
    > kindest/node build should appear on Docker
    (b) Install cloud-provider-kind
    ```
    go install sigs.k8s.io/cloud-provider-kind@latest
    ```

    (c) Create Load Balancer Service
    ```
    cloud-provider-kind -enable-lb-port-mapping
    ```
    > Envoy proxy build should appear on Docker for every 'service' of type 'LoadBalancer' resource to be created steps bellow

    (d) Setup Dashboard for better visualization
    ``` 
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

    # Check if its working
    kubectl get pod -n kubernetes-dashboard

    # Create a ServiceAccount and ClusterRoleBinding to provide admin access to the newly
    kubectl create serviceaccount -n kubernetes-dashboard admin-user
    
    kubectl create clusterrolebinding -n kubernetes-dashboard admin-user --clusterrole cluster-admin --serviceaccount=kubernetes-dashboard:admin-user

    ```

    (e) Get token for dashboard
    ```
    token=$(kubectl -n kubernetes-dashboard create token admin-user)
    ```
    ```
    echo $token
    ```

    (f) Access Dashboard on this [link](http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/) after running the following command:

    ```
    kubectl proxy
    ```
    > Remember to use the token from the previous steps

2) Deploy a sample application
    
    (a) Using Bookinfo istio provided application.
    ```
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.27/samples/bookinfo/platform/kube/bookinfo.yaml

    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.27/samples/bookinfo/platform/kube/bookinfo-versions.yaml
    ```

    (b) Create ingress gateway to access the Application from outside the cluster
    ```
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.27/samples/bookinfo/gateway-api/bookinfo-gateway.yaml
    ```
    > By default, Istio creates a LoadBalancer service for a gateway. As you will access this gateway by a tunnel, you don’t need a load balancer. Change the service type to ClusterIP by annotating the gateway
    
    ```
    kubectl annotate gateway bookinfo-gateway networking.istio.io/service-type=ClusterIP --namespace=default
    ```

    (c) Access the application creating a port-forward for local machine to the service from the gateway provisioned
    ```
    kubectl port-forward svc/bookinfo-gateway-istio 8080:80
    ```
    Now the `productpage` is accessible through <http://localhost:8080/productpage>

3) Set applications to use istio ambient mesh.

    (a) To enable all pods to be part of the ambient mesh, add this label:
    ```
    kubectl label namespace default istio.io/dataplane-mode=ambient
    ```

    (b) Visualize metrics collected by istio dashboard, Kiali and Prometheus metrics engine.
    ```
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.27/samples/addons/prometheus.yaml

    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.27/samples/addons/kiali.yaml
    ```
    
    (d) Access Dashboard
    ```
    istioctl dashboard kiali
    ```

    > You can generate some access metrics `for i in $(seq 1 100); do curl -sSI -o /dev/null http://localhost:8080/productpage; done`

4) Authorization on the mesh

    (a) Set Authorization policy on Layer 4

    ```
    kubectl apply -f l4_authz_policy.yaml
    ```
    > This policy is applied to pods with the app: productpage label, and it allows calls only from the the service account cluster.local/ns/default/sa/bookinfo-gateway-istio

    (b) Set waypoint (envoy deploy)

    ```
    istioctl waypoint apply --enroll-namespace --wait
    ```

    (c) Create Authorization policy on Layer 7
    
    ```
    kubectl apply -f l7_authz_policy.yaml
    ```

5) OPA on the mesh

    (a) Using the opa policy on [policy.rego](./policy.rego), create a configMap
    
    ```bash
    kubectl create configmap opa-policy --from-file=policy.rego
    ```

    (b) Then apply the opa engine
    
    ```bash
    kubectl apply -f opa-deployment.yaml
    ```

    (c) Update istio configuration to extend opa provider.

    ```bash
    kubectl edit configmap istio -n istio-system
    ```
    Add to the "mesh" section

    ```yaml
      mesh: |-
        # Add this extensionProviders block
        extensionProviders:
        - name: opa-authorizer
            envoyExtAuthzGrpc:
            service: opa.default.svc.cluster.local
            port: 9191
    ```

    (d) Then create an Authorization Policy ([opa-auth-policy.yaml](./opa-auth-policy.yaml)) for that targets traffic going through the waypoint and uses your new OPA provider. 

    ```bash
    kubectl apply -f opa-auth-policy.yaml
    ```

    (e) Test it
    
    ```
    # Should not work
    curl http://localhost:8080/productpage -v

    # Should work
    curl http://localhost:8080/productpage  -H "x-user: admin" -v
    ```

6. Split traffic between services

    Let’s configure traffic routing to send 90% of requests to reviews v1 and 10% to reviews v2:

    (a) Create services

    ```bash
    kubectl apply -f review_1_svc.yaml
    kubectl apply -f review_2_svc.yaml
    ```

    (b) Split traffic incoming from service Reviews into those two services, with 90% into reviews-v1 and 10% to reviews-v2

    ```bash
    kubectl apply -f http_route.yaml
    ```

    (c) Generate traffic and check on the dashboard

    ```bash
    kubectl exec deploy/curl -- sh -c "for i in \$(seq 1 100); do curl -s http://productpage:9080/productpage | grep reviews-v.-; done"
    ```
