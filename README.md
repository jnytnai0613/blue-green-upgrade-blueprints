# EKS Blue-Green Upgrade with Terraform

このディレクトリは、**Amazon EKS クラスターの Blue-Green アップグレード戦略**を Terraform を用いて実現するための構成です。</br>
各バージョンの EKS クラスター（Blue と Green）を並列に管理し、Route53 の加重レコードを活用してトラフィックを段階的に切り替える構成になっています。</br>
※本ディレクトリの構成は、 以下文献を参考にし、簡略化したものです。</br>
  また、前者の文献ではバージョンの関係上、AWS LoadBalancer ControllerとExternalDNSでPod Identityを設定せず、アプリケーションでの設定のみとなっておりましたが、本ディレクトリ手順での最新バージョンでは設定可能となっています。
- [EKS Pod Identity を活用して Terraform でプロビジョニングした EKS を Blue/Green アップグレードしてみた](https://dev.classmethod.jp/articles/eks-pod-identity-terraform-blue-green-upgrade/)
- [Amazon EKS Blueprints for Terraform](https://github.com/aws-ia/terraform-aws-eks-blueprints/tree/main/patterns/blue-green-upgrade)

## ディレクトリ構成
EKSを作成するModuleは[こちらを参照](https://github.com/jnytnai0613/terraform_for_aws_practice/tree/main/modules/services/blue-green-cluster)
```
.
├── system
│   ├── assets        # サンプルアプリや各種yamlファイル
│   ├── blue-cluster  # EKS 1.33 クラスター (Green)
│   ├── green-cluster # EKS 1.32 クラスター (Blue)
│   ├── common        # 共通の VPC, Route53 Hosted Zone
│
└── modules/cluster # EKS作成モジュール
```

## 使用技術
- Terraform v1.12.2
- AWS EKS (Blue: 1.32 / Green: 1.33)
  - Pod Identity
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.13/)
- [ExternalDNS](https://github.com/kubernetes-sigs/external-dns)
- Route53 Weighted Routing

## Pod Identityについて
EKSのServiceAccountに対してIAMロールを紐づける仕組みとして、
[AWS公式のModule terraform-aws-eks-pod-identity](https://registry.terraform.io/modules/terraform-aws-modules/eks-pod-identity/aws/latest)の利用も可能です。しかしこのモジュールでは、[aws_eks_pod_identity_associationリソース](https://registry.terraform.io/providers/hashicorp/aws/5.37.0/docs/resources/eks_pod_identity_association)の`role_arn` に指定されるロールが、新規作成されることを前提としています。</br>
以下は、該当Module内のコード（[該当箇所のリンク](https://github.com/terraform-aws-modules/terraform-aws-eks-pod-identity/blob/6d4aa31990e4179640c869505169ebc78f200e10/main.tf#L183-L196)）です。

```hcl
resource "aws_eks_pod_identity_association" "this" {
  for_each = { for k, v in var.associations : k => v if var.create }


  cluster_name    = try(each.value.cluster_name, var.association_defaults.cluster_name)
  namespace       = try(each.value.namespace, var.association_defaults.namespace)
  service_account = try(each.value.service_account, var.association_defaults.service_account)
  role_arn        = aws_iam_role.this[0].arn


  tags = merge(var.tags, try(each.value.tags, var.association_defaults.tags, {}))
}
```
今回はEKSクラスターをBlue/Greenの2系統で構築し、それぞれで**同一のIAMロール**を使用する必要があります。そのため、新規ロール作成が前提となっている公式モジュールでは要件を満たせません。
そこで、`aws_eks_pod_identity_association`リソースをモジュール経由ではなく直接コード内に記述し、あらかじめ作成済みのIAMロールARNを明示的に指定する形でPod Identityを設定しています。
```hcl
resource "aws_eks_pod_identity_association" "external-dns-identity" {
  cluster_name    = module.eks.cluster_name
  namespace       = local.external_dns_namespace
  service_account = local.external_dns_serviceaccount
  role_arn        = data.terraform_remote_state.common.outputs.pod_external_dns_role_arn
}
```

## 前提条件
- 各ディレクトリのBackendのBucket名やKeyなどは任意の名前に変更されていること
- Route53へドメインおよびホストゾーンが登録されていること
- サンプルアプリのDockerコンテナがビルドされていること

## 手順
### 1. 共通リソースデプロイ
```sh
cd common
terraform init
terraform plan
terraform apply
```
ここで以下リソースがデプロイされます。
- VPC
- Subnet
- 事前に登録したドメインに紐づくサブドメイン
- Pod Identityに紐づけるIAMロール

#### コンテナをECRへPush
```sh
$ aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin <ECRホスト名>
$ docker tag blue-green-ecr:latest <ECRホスト名>/image:latest
$ docker push <ECRホスト名>/image:latest
```

#### Amazon DynamoDBへデータ投入
```sh
# キーは任意の値とする
$ aws dynamodb put-item --table-name test-dynamodb --item '{"UserId": {"S": "3"}}'
```

### 2. Blue EKSクラスタデプロイ
```sh
$ cd syste/blue-cluster
$ terraform init
$ terraform plan
$ terraform apply
```
ここで、先に作成したIAMロールと、EKSクラスタ、namespace、ServiceAccountを紐づけます。</br>
この時、AWS LoadBalancer Controller、ExternalDNS、アプリケーションに紐づけます。</br>
また、EKSではPod Identity Agent Add-onを有効化します。

#### AWS Load Balancer Controller、ExternalDNS、アプリケーションデプロイ
##### ALB Controller
```sh
$ helm repo add eks https://aws.github.io/eks-charts
$ helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=blue
```

##### External DNS
```sh
$ kubectl apply -f system/assets/external-dns/external-dns.yaml
```

##### アプリケーション
```sh
$ kubectl apply -f system/assets/sample-app/blue/fastapi.yaml
```
この時、ExternalDNSによって、Route53のサブドメインへAレコードが登録されますが、ルーティングポリシーの重みづけを30にします。

### 3. Green EKSクラスタデプロイ
```sh
$ cd syste/blue-cluster
$ terraform init
$ terraform plan
$ terraform apply
```
ここで、Blue面と同じく、先に作成したIAMロールと、EKSクラスタ、namespace、ServiceAccountを紐づけます。</br>
この時、AWS LoadBalancer Controller、ExternalDNS、アプリケーションに紐づけます。</br>
また、EKSではPod Identity Agent Add-onを有効化します。

#### AWS Load Balancer Controller、ExternalDNS、アプリケーションデプロイ
Blueの面と同じ構成でGreen面もデプロイしていきます。
##### ALB Controller
```sh
$ helm repo add eks https://aws.github.io/eks-charts
$ helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=green
```

##### External DNS
```sh
$ kubectl apply -f system/assets/external-dns/external-dns.yaml
```

##### アプリケーション
```sh
$ kubectl apply -f system/assets/sample-app/green/fastapi.yaml
```
Blueと同じドメインでIngressをデプロイします。</br>
この時、ExternalDNSによってRoute53のサブドメインへ、Blue面とは異なりレコードIDが"test-green"となるAレコードが登録されますが、今回はルーティングポリシーの重みづけを70にします。

### 4. 切り替え
1. しばらく両クラスタを稼働させ、Green面の新クラスタに問題がないことを確認します。
1. Blue面のIngressの `.metadata.annotation.external-dns.alpha.kubernetes.io/aws-weigh` を 0 に変更し、再デプロイします。
1. Route53のレコードIDが"test-blue"になっているAレコード、AAAAレコード、TXTレコードを削除し、ExternalDNSによって再度登録されるのを待ちます。
1.  同じくGreen面のIngressの `.metadata.annotation.external-dns.alpha.kubernetes.io/aws-weigh` を 100 に変更し、再デプロイします。
1. Route53のレコードIDが"test-green"になっているAレコード、AAAAレコード、TXTレコードを削除し、ExternalDNSによって再度登録されるのを待ちます。
1. これでGreen面の新クラスタに全部のトラフィックが流れます。問題ないことを確認後、以下コマンドでBlue面を削除します。
```sh
$ cd blue-green-upgrade/blue-cluster
$ terraform destroy
```
