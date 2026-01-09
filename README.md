# EKS Playground with Terraform

本リポジトリは、**Amazon EKS クラスターの Blue-Green アップグレード戦略やその他検証** を Terraform を用いて実現するための構成です。</br>
Blue-Greenする場合は、各バージョンの EKS クラスター（Blue と Green）を並列に管理し、Route53 の加重レコードを活用してトラフィックを段階的に切り替える構成になっています。</br>
以下主にBlue-Greenする場合の説明となっていますが、その他EKSを使った検証はなんでもできます。
※本ディレクトリの構成は、 以下文献を参考にし、簡略化したものです。</br>
  また、前者の文献ではバージョンの関係上、AWS LoadBalancer ControllerとExternalDNSでPod Identityを設定せず、アプリケーションでの設定のみとなっておりましたが、本手順での最新バージョンでは設定可能となっています。
- [EKS Pod Identity を活用して Terraform でプロビジョニングした EKS を Blue/Green アップグレードしてみた](https://dev.classmethod.jp/articles/eks-pod-identity-terraform-blue-green-upgrade/)
- [Amazon EKS Blueprints for Terraform](https://github.com/aws-ia/terraform-aws-eks-blueprints/tree/main/patterns/blue-green-upgrade)

> [!NOTE]
> さらに今回はArgo CDのApp of Appsパターンを導入し、Load Balancerや、ドメイン、アプリの払い出しを簡略化しています。</br>
> App of Appsパターンでは、Sync Wave機能を使用し、各Applicationの起動と削除順序を制御しています。
> ```yaml
> apiVersion: argoproj.io/v1alpha1
> kind: Application
> metadata:
>   name: aws-load-balancer-controller
>   namespace: argocd
>   annotations:
>     argocd.argoproj.io/sync-wave: "-1"
> ```
> なお、今回は全てCLIでの操作を前提としていますが、Argo CDのGUI画面を使用して操作も可能です。

## ディレクトリ構成
EKSを作成するModuleは[こちらを参照](https://github.com/jnytnai0613/eks-playground/tree/main/modules/cluster)
```
.
├── modules/cluster # EKS作成モジュール
└──system
│   ├── assets        # サンプルアプリや各種yamlファイル
│   ├── blue-cluster  # EKS 1.33 クラスター (Green)
│   ├── green-cluster # EKS 1.32 クラスター (Blue)
│   ├── common        # 共通の VPC, Route53 Hosted Zone, CodeBuild
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
[AWS公式のModule terraform-aws-eks-pod-identity](https://registry.terraform.io/modules/terraform-aws-modules/eks-pod-identity/aws/latest)の利用も可能です。しかしこのモジュールでは、[aws_eks_pod_identity_associationリソース](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association)の`role_arn` に指定されるロールが、新規作成されることを前提としています。</br>
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
- Route53へドメインおよびホストゾーンが登録されていること
- [argocd CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/)をインストールしていること

## 手順
### 事前準備
#### 以下のGitHubリポジトリURLを任意のものに変える

  現在GitHubリポジトリURLは本リポジトリを指していますので、必ずご自身でフォークしたリポジトリ名に置き換えてください。
  - [system/assets/argocd/app-of-apps-blue.yaml](https://github.com/jnytnai0613/eks-playground/blob/main/system/assets/argocd/app-of-apps-blue.yaml#L9)
  - [system/assets/argocd/app-of-apps-green.yaml](https://github.com/jnytnai0613/eks-playground/blob/main/system/assets/argocd/app-of-apps-green.yaml#L9)
  - [system/assets/argocd/base/externaldns-applications.yaml](https://github.com/jnytnai0613/eks-playground/blob/main/system/assets/argocd/base/externaldns-applications.yaml#L13)
  - [system/assets/argocd/base/fastapi-applications.yaml](https://github.com/jnytnai0613/eks-playground/blob/main/system/assets/argocd/base/fastapi-applications.yaml#L13)
  - [system/common/codebuild/main.tf](https://github.com/jnytnai0613/eks-playground/blob/main/system/common/codebuild/main.tf#L125)

#### backendのS3を作成する

  EKSをデプロイするmoduleではterraform_remote_stateを使用して、VPC IDなどを取得する構成としているため、以降の手順を実施する前に、以下参考資料のドキュメントを参考にbackend用S3をデプロイして、stateを管理できるようにしておく必要があります。</br>
  なお、S3のBucket名は任意のものに適宜置き換えてください。</br>
  参考：[S3でtfstateファイルを管理する](https://qiita.com/pir0ot/items/aab7ff19b78c818779a7)</br>
  今回は`system/common/s3`にbackend用のS3をデプロイするコードを置いていますので、以下手順でも準備を完了することができます。</br>

  1. backend.tfの拡張子を.bakなどに変更
  1. `terraform init` -> `terraform apply`実行
  1. backend.tfの拡張子を元に戻す
  1. `terraform init`実行

  最後のterraform initにより、ローカルのtfstateが検知され、自動でS3にコピーされます。</br>
  対話式なので、S3にコピーするか尋ねられたら、yesを入力して処理を完了してください。

### 1. 共通リソースデプロイ
#### 1.1. CodeBuildデプロイ
```sh
$ cd system/common/codebuild
$ terraform init
$ terraform plan
$ terraform apply
```

> [!IMPORTANT]
> このプロジェクトでは、AWS CodeConnections（aws_codeconnections_connection.github）を使ってGitHubからのWebhookを受け取り、CIのトリガーにしています。
> ただし、Webhook は CodeBuild と同時にデプロイできません。まずは AWS CodeConnections を承認し、GitHub リポジトリに GitHub App をインストールしてください。
>
> 参考：[AWS CodeBuild入門：セキュアなCIをTerraformで構築したよ](https://zenn.dev/junya0530/articles/8f3494d0ee8beb)
>
> 初期状態では Webhook のリソースはコメントアウトしています。AWS CodeConnections の承認が完了したら、コメントアウトを解除して terraform apply を再実行してください。

#### 1.2. コンテナのBuild&Push
`system/assets/sample-app/container` ディレクトリのファイルを変更することでCIを走らせることが可能です。</br>
CIは以下の処理を行っています。
- ECRへのログイン
- コンテナのBiuld
- ECRへコンテナのPush

buildspec.ymlは`system/assets/sample-app/container/buildspec.yml`を参照ください。

#### 1.3. Network系AWSリソースデプロイ
```sh
$ cd system/common/network
$ terraform init
$ terraform plan
$ terraform apply
```
ここで以下リソースがデプロイされます。
- VPC
- Subnet
- 事前に登録したドメインに紐づくサブドメイン
- Pod Identityに紐づけるIAMロール

> [!NOTE]
> 本構成では、コスト最適化の観点から、AWS内外を問わず通信は基本的にNAT Gateway経由としています。</br>
> 通常、EKSからDynamoDBなどのAWSサービスへの通信にはVPCエンドポイント（Gateway Endpoint）を用いるケースもありますが、以下の事例にもある通り、NAT Gatewayを介した通信でもセキュリティを維持しつつコストを抑えることが可能です。
>
> 参考：[【AWSコスト最適化】VPC エンドポイントを消すだけでセキュリティそのままにコストが節約できた](https://zenn.dev/simpleform_blog/articles/f048edb9efd2b2)
>
> 現在はコメントしてますが、必要に応じてVPC Endpointを追加する構成も柔軟に対応可能です。

#### 1.4. Amazon DynamoDBへデータ投入
```sh
# キーは任意の値とする
$ aws dynamodb put-item --table-name test-dynamodb --item '{"UserId": {"S": "3"}}'
```

### 2. Blue EKSクラスタデプロイ
```sh
$ cd system/blue-cluster
$ terraform init
$ terraform plan
$ terraform apply
```
このステップでは、EKS クラスターのデプロイと同時に Pod Identity Agent Add-on を有効化し、Namespace、ServiceAccount、IAM ロールを紐付けます。
これにより、Pod Identity を通じて IAM ロールを利用できるようにする設定が完了となります。対象となるコンポーネントは以下の通りです。
- AWS Load Balancer Controller
- ExternalDNS
- アプリケーション用 ServiceAccount

### ３. Blue EKSクラスタArgo CDインストール
#### 3.1. インストール
```sh
# https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd
$ helm repo add argo https://argoproj.github.io/argo-helm
$ helm install -n argocd argocd argo/argo-cd --create-namespace
```
#### 3.2. Applicationインストール
```sh
$ kubectl apply -f system/assets/argocd/app-of-apps-blue.yaml
```

ここまでくると、以下のようにArgo CDでApp of AppsパターンでApplicationが管理されていることが確認できるようになります。
```sh
$ argocd app get app-of-apps
Name:               argocd/app-of-apps
Project:            default
Server:             https://kubernetes.default.svc
Namespace:          argocd
URL:                https://argocd.example.com/applications/app-of-apps
Source:
- Repo:             https://github.com/jnytnai0613/eks-playground
  Target:           HEAD
  Path:             system/assets/argocd/overlays/green
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        Synced to HEAD (fe76e47)
Health Status:      Healthy

GROUP        KIND         NAMESPACE  NAME                          STATUS  HEALTH  HOOK  MESSAGE
argoproj.io  Application  argocd     aws-load-balancer-controller  Synced                application.argoproj.io/aws-load-balancer-controller created
argoproj.io  Application  argocd     externaldns                   Synced                application.argoproj.io/externaldns created
argoproj.io  Application  argocd     fastapi                       Synced                application.argoproj.io/fastapi created
```

### 4. Green EKSクラスタデプロイ
```sh
$ cd system/blue-cluster
$ terraform init
$ terraform plan
$ terraform apply
```
ここで、Blue面と同じく、EKS クラスターのデプロイと同時に Pod Identity Agent Add-on を有効化し、Namespace、ServiceAccount、IAM ロールを紐付けます。

### 5. Green EKSクラスタへのArgo CDインストール
#### 5.1. インストール
```sh
# https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd
$ helm repo add argo https://argoproj.github.io/argo-helm
$ helm install -n argocd argocd argo/argo-cd --create-namespace
```
#### 5.2. Applicationインストール
```sh
$ kubectl apply -f system/assets/argocd/app-of-apps-green.yaml
```

Blueと同じドメインでIngressをデプロイしてます。</br>
この時、ExternalDNSによってRoute53のサブドメインへ、Blue面とは異なりレコードIDが"test-green"となるAレコードが登録されます。</br>
今回はルーティングポリシーの重みづけをBlueを70、Greenを30にしています。</br>
次のステップで重みづけを変更し、面の切り替えを行います。

### 4. 切り替え
1. しばらく両クラスタを稼働させ、Green面の新クラスタに問題がないことを確認します。
1. Blue面のsystem/assets/sample-app/overlays/blue/ingress-patch.yaml内の `.metadata.annotation.external-dns.alpha.kubernetes.io/aws-weigh` を 0 に変更し、Ingressを削除して再作成します。（削除によりApplicationが再作成します）
1. Route53のレコードIDが"test-blue"になっているAレコード、AAAAレコード、TXTレコードを削除し、ExternalDNSによって再度登録されるのを待ちます。
1.  同じくGreen面のsystem/assets/sample-app/overlays/green/ingress-patch.yaml内の `.metadata.annotation.external-dns.alpha.kubernetes.io/aws-weigh` を 100 に変更し、再作成します。
1. Route53のレコードIDが"test-green"になっているAレコード、AAAAレコード、TXTレコードを削除し、ExternalDNSによって再度登録されるのを待ちます。
1. これでGreen面の新クラスタに全部のトラフィックが流れます。問題ないことを確認後、以下コマンドでBlue面を削除します。
```sh
# Argo CDのパスワード確認
$ kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# App of Appsパターンの親Application削除
$ kubectl port-forward service/argocd-server -n argocd 8080:443
$ argocd login localhost:8080 --name admin --password XXXXXX
$ argocd app delete app-of-apps

# クラスタ削除
$ cd system/blue-cluster
$ terraform destroy
```
