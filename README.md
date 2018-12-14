# cloudrt setup cluster
This readme is developed following [Terraform guide for seeting up EKS](https://www.terraform.io/docs/providers/aws/guides/eks-getting-started.html#configuring-kubectl-for-eks).
[Guide for setting up cluster autoscaler for EKS](https://medium.com/@alejandro.millan.frias/cluster-autoscaler-in-amazon-eks-d9f787176519)
[Setting up service account for tiller](https://medium.com/@zhaimo/using-helm-to-install-application-onto-aws-eks-36840ff84555)

## Preparation
* [Install aws-cli](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html)
* [Install kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [Install aws-iam-authenticator](https://www.google.com/search?client=safari&rls=en&q=install+aws-iam-authenticator&ie=UTF-8&oe=UTF-8)
* [Install Helm](https://github.com/helm/helm)

## Creating cluster
```bash
terraform init
terraform apply
# type yes to proceed
```
A sample output looks like 
```bash
Apply complete! Resources: 23 added, 0 changed, 0 destroyed.

Outputs:

config_map_aws_auth = 

apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: arn:aws:iam::387291866455:role/terraform-eks-cloudrt-node
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
```
copy the config_map_aws_auth field into a yaml file
```yaml
# config_map_auth.yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: arn:aws:iam::387291866455:role/terraform-eks-cloudrt-node
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
```
to be used after we configure Kubernetes.

We next need to setup authentication to Kubernetes master.
```bash
aws eks update-kubeconfig --name cloudrt-cluster
> Added new context arn:aws:eks:us-west-2:387291866455:cluster/cloudrt-cluster to /Users/foobar/.kube/config
```

Apply the yaml file saved earlier.
```bash
kubectl apply -f config_map_auth.yml
```
## Install cluster autoscaler
```bash
kubectl create serviceaccount tiller --namespace kube-system
kubectl apply -f tiller-rbac.yml
helm init --service-account tiller
helm install stable/cluster-autoscaler --name autoscaler --set autoDiscovery.clusterName=cloudrt-cluster --set rbac.create=true --set sslCertPath=/etc/kubernetes/pki/ca.crt --set awsRegion=us-west-2
```

To test the autoscaler, you can run
```bash
kubectl run example --image=nginx --replicas=30
kubectl get configmap cluster-autoscaler-status -o yaml
kubectl delete deployment example
```

## Scratch
* The nodes have label `beta.kubernetes.io/instance-type=m4.large`
* [Autoscaler](https://medium.com/@alejandro.millan.frias/cluster-autoscaler-in-amazon-eks-d9f787176519)