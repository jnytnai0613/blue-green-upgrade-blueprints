# EKS Blue-Green Upgrade with Terraform

## 📋 リポジトリ概要

本リポジトリは、**Amazon EKS クラスターの Blue-Green アップグレード戦略**を Terraform を用いて実現するための完全なソリューションです。

### 🎯 目的
- EKS クラスターのバージョンアップを **ダウンタイムゼロ** で実現
- 本番環境でのリスクを最小化した安全なアップグレード手法の提供
- Infrastructure as Code による再現可能で自動化された環境構築

### 🏗️ アーキテクチャの特徴
- **並列運用**: Blue（現行）と Green（新バージョン）の2つのEKSクラスターを同時稼働
- **段階的切り替え**: Route53 の加重レコードを使用したトラフィックの段階的移行
- **自動化**: ArgoCD を活用した App of Apps パターンでのアプリケーション管理
- **セキュリティ**: Pod Identity を使用した IAM ロールとの安全な連携

### 🔄 Blue-Green アップグレードフロー
```
1. Blue クラスター (現行版) でサービス稼働
2. Green クラスター (新バージョン) を並列構築
3. Route53 で段階的にトラフィックを Blue → Green に移行
4. Green での安定性確認後、Blue クラスターを削除
```

### 📚 参考文献
本リポジトリは以下の文献を参考にし、最新のベストプラクティスを適用して改良したものです：
- [EKS Pod Identity を活用して Terraform でプロビジョニングした EKS を Blue/Green アップグレードしてみた](https://dev.classmethod.jp/articles/eks-pod-identity-terraform-blue-green-upgrade/)
- [Amazon EKS Blueprints for Terraform](https://github.com/aws-ia/terraform-aws-eks-blueprints/tree/main/patterns/blue-green-upgrade)

## 🚀 主要な技術改善点

### ArgoCD App of Apps パターンの採用
- **統合管理**: Load Balancer、ドメイン、アプリケーションの一元管理を実現
- **順序制御**: Sync Wave 機能による各 Application の起動・削除順序の制御
- **可視化**: ArgoCD GUI による直感的な操作とステータス確認

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: aws-load-balancer-controller
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"  # 他のアプリより先に起動
```

### Pod Identity の完全対応
最新バージョンの EKS では Pod Identity が正式サポートされ、以下のコンポーネントで活用：
- AWS Load Balancer Controller
- ExternalDNS  
- アプリケーション用 ServiceAccount

## 📁 ディレクトリ構成

EKSを作成するModuleは[こちらを参照](https://github.com/jnytnai0613/blue-green-upgrade-blueprints/tree/main/modules/cluster)

```
.
├── modules/cluster     # EKS クラスター作成用の再利用可能なモジュール
│   ├── main.tf        # EKS クラスターとノードグループの定義
│   ├── variables.tf   # 入力変数の定義
│   └── outputs.tf     # 出力値の定義
└── system/
    ├── assets/        # ArgoCD アプリケーション定義とサンプルアプリ
    │   ├── argocd/    # App of Apps パターンの設定ファイル
    │   ├── external-dns/ # ExternalDNS の設定
    │   └── sample-app/   # サンプルアプリケーション
    ├── blue-cluster/  # EKS 1.32 クラスター（Blue 環境）
    ├── green-cluster/ # EKS 1.33 クラスター（Green 環境）  
    └── common/        # 共通リソース
        ├── network/   # VPC、サブネット、Route53
        ├── codebuild/ # CI/CD パイプライン
        └── s3/        # Terraform state 用 S3
```

### 各ディレクトリの役割

| ディレクトリ | 説明 | 含まれるリソース |
|-------------|------|-----------------|
| `modules/cluster` | 再利用可能な EKS モジュール | EKS クラスター、ノードグループ、Pod Identity |
| `system/common/network` | ネットワーク基盤 | VPC、サブネット、Route53、IAM ロール |
| `system/common/codebuild` | CI/CD 基盤 | CodeBuild プロジェクト、GitHub 連携 |
| `system/blue-cluster` | Blue 環境 | EKS 1.32 クラスター |
| `system/green-cluster` | Green 環境 | EKS 1.33 クラスター |
| `system/assets` | アプリケーション定義 | ArgoCD アプリ、サンプルアプリ |

## 🛠️ 使用技術

### インフラストラクチャ
| 技術 | バージョン | 用途 |
|------|-----------|------|
| **Terraform** | v1.12.2 | インフラストラクチャのコード化 |
| **AWS EKS** | Blue: 1.32 / Green: 1.33 | Kubernetes クラスター基盤 |
| **Pod Identity** | - | IAM ロールとの安全な連携 |

### Kubernetes アドオン
| コンポーネント | 説明 |
|---------------|------|
| [**AWS Load Balancer Controller**](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.13/) | AWS ALB/NLB の自動管理 |
| [**ExternalDNS**](https://github.com/kubernetes-sigs/external-dns) | Route53 レコードの自動管理 |
| **ArgoCD** | GitOps による継続的デプロイメント |

### ネットワーク構成
| 技術 | 用途 |
|------|------|
| **Route53 Weighted Routing** | Blue-Green 間のトラフィック制御 |
| **NAT Gateway** | コスト効率的なアウトバウンド通信 |
| **Application Load Balancer** | HTTP/HTTPS トラフィック分散 |

## 🔐 Pod Identity について

### 技術的背景
EKS の ServiceAccount に対して IAM ロールを紐づける仕組みとして、従来の IRSA（IAM Roles for Service Accounts）に加えて、より新しい **Pod Identity** 機能を採用しています。

### 設計上の課題と解決策
AWS 公式の [terraform-aws-eks-pod-identity モジュール](https://registry.terraform.io/modules/terraform-aws-modules/eks-pod-identity/aws/latest) は新規 IAM ロール作成を前提としていますが、本構成では Blue-Green 両クラスターで **同一の IAM ロール** を共有する必要があります。

#### 公式モジュールの制約
```hcl
# 公式モジュールでは role_arn が新規作成されるロールに固定
resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = try(each.value.cluster_name, var.association_defaults.cluster_name)
  namespace       = try(each.value.namespace, var.association_defaults.namespace)
  service_account = try(each.value.service_account, var.association_defaults.service_account)
  role_arn        = aws_iam_role.this[0].arn  # ← 新規作成されるロール
}
```

#### 本構成での解決策
```hcl
# 既存の IAM ロール ARN を明示的に指定
resource "aws_eks_pod_identity_association" "external-dns-identity" {
  cluster_name    = module.eks.cluster_name
  namespace       = local.external_dns_namespace
  service_account = local.external_dns_serviceaccount
  role_arn        = data.terraform_remote_state.common.outputs.pod_external_dns_role_arn
}
```

この方法により、Blue-Green 両環境で一貫したセキュリティポリシーを維持しながら、効率的なリソース管理を実現しています。

## ✅ 前提条件

### 必要な環境
- **AWS CLI**: 適切な権限を持つ AWS アカウントでの認証済み
- **Terraform**: v1.12.2 以上
- **kubectl**: Kubernetes クラスター操作用
- **ArgoCD CLI**: [公式インストールガイド](https://argo-cd.readthedocs.io/en/stable/cli_installation/) に従ってインストール

### AWS リソースの事前準備
- **Route53 ホストゾーン**: 使用するドメインのホストゾーンが事前に登録済みであること
- **IAM 権限**: EKS、VPC、Route53、S3、CodeBuild などのリソース作成権限

### ネットワーク設計について
本構成では、コスト最適化の観点から以下の設計を採用しています：

> **💡 ネットワーク戦略**
> 
> AWS 内外を問わず、基本的に **NAT Gateway 経由** での通信を採用しています。
> 一般的には DynamoDB などの AWS サービスへの通信には VPC エンドポイント（Gateway Endpoint）を使用するケースもありますが、以下の理由により NAT Gateway を選択：
> 
> - **コスト効率**: VPC エンドポイントの月額費用 vs NAT Gateway のデータ転送費用
> - **運用簡素化**: エンドポイント管理の複雑さを回避
> - **セキュリティ維持**: 適切なセキュリティグループとネットワーク ACL により十分なセキュリティを確保
> 
> 参考：[VPC エンドポイントを消すだけでセキュリティそのままにコストが節約できた](https://zenn.dev/simpleform_blog/articles/f048edb9efd2b2)
> 
> 必要に応じて VPC エンドポイントを追加する構成も柔軟に対応可能です。

## 🚀 セットアップ手順

### 事前準備

#### 1. GitHub リポジトリ URL の更新
以下のファイル内の GitHub リポジトリ URL を、**ご自身でフォークしたリポジトリ** に変更してください：

| ファイルパス | 変更箇所 |
|-------------|----------|
| `system/assets/argocd/app-of-apps-blue.yaml` | [L9](https://github.com/jnytnai0613/blue-green-upgrade-blueprints/blob/main/system/assets/argocd/app-of-apps-blue.yaml#L9) |
| `system/assets/argocd/app-of-apps-green.yaml` | [L9](https://github.com/jnytnai0613/blue-green-upgrade-blueprints/blob/main/system/assets/argocd/app-of-apps-green.yaml#L9) |
| `system/assets/argocd/base/externaldns-applications.yaml` | [L13](https://github.com/jnytnai0613/blue-green-upgrade-blueprints/blob/main/system/assets/argocd/base/externaldns-applications.yaml#L13) |
| `system/assets/argocd/base/fastapi-applications.yaml` | [L13](https://github.com/jnytnai0613/blue-green-upgrade-blueprints/blob/main/system/assets/argocd/base/fastapi-applications.yaml#L13) |
| `system/common/codebuild/main.tf` | [L125](https://github.com/jnytnai0613/blue-green-upgrade-blueprints/blob/main/system/common/codebuild/main.tf#L125) |

#### 2. Terraform Backend 用 S3 セットアップ

本構成では `terraform_remote_state` を使用して共通リソース（VPC ID など）を参照するため、事前に Backend 用 S3 バケットの準備が必要です。

```bash
# 1. S3 ディレクトリに移動
cd system/common/s3

# 2. backend.tf を一時的に無効化
mv backend.tf backend.tf.bak

# 3. 初期デプロイ（ローカル state）
terraform init
terraform apply

# 4. backend.tf を復元
mv backend.tf.bak backend.tf

# 5. state を S3 に移行
terraform init
# → "Do you want to copy existing state to the new backend?" で "yes" を入力
```

> **📝 参考**: [S3でtfstateファイルを管理する](https://qiita.com/pir0ot/items/aab7ff19b78c818779a7)
>
> S3 バケット名は任意のものに適宜変更してください。

### デプロイメント手順

#### 1. 共通インフラストラクチャのデプロイ

##### 1.1. CodeBuild CI/CD パイプラインの構築
```bash
cd system/common/codebuild
terraform init
terraform plan
terraform apply
```

> **⚠️ 重要: AWS CodeConnections の設定**
> 
> このプロジェクトでは、AWS CodeConnections を使用して GitHub からの Webhook を受け取り、CI をトリガーしています。
> 
> **初回デプロイ後の追加設定:**
> 1. AWS コンソールで CodeConnections の承認を実行
> 2. GitHub リポジトリに GitHub App をインストール
> 3. `main.tf` 内の Webhook リソースのコメントアウトを解除
> 4. `terraform apply` を再実行
> 
> 参考：[AWS CodeBuild入門：セキュアなCIをTerraformで構築したよ](https://zenn.dev/junya0530/articles/8f3494d0ee8beb)

##### 1.2. コンテナイメージのビルド & プッシュ
```bash
# sample-app のコンテナファイルを変更して CI をトリガー
# または手動でビルド
cd system/assets/sample-app/container
# ファイルを変更してコミット・プッシュ
```

**CI パイプラインの処理内容:**
- ECR への認証
- Docker イメージのビルド
- ECR へのイメージプッシュ

ビルド設定は `system/assets/sample-app/container/buildspec.yml` を参照してください。

##### 1.3. ネットワークリソースのデプロイ
```bash
cd system/common/network
terraform init
terraform plan
terraform apply
```

**デプロイされるリソース:**
- VPC とサブネット
- Route53 サブドメイン（事前登録ドメインに紐づく）
- Pod Identity 用 IAM ロール
- セキュリティグループ

##### 1.4. サンプルデータの準備
```bash
# DynamoDB テーブルにテストデータを投入
aws dynamodb put-item \
  --table-name test-dynamodb \
  --item '{"UserId": {"S": "3"}}'
```

#### 2. Blue EKS クラスター（現行環境）のデプロイ

```bash
cd system/blue-cluster
terraform init
terraform plan
terraform apply
```

**このステップで実行される処理:**
- EKS 1.32 クラスターの作成
- Pod Identity Agent Add-on の有効化
- 以下コンポーネント用の Namespace と ServiceAccount の作成:
  - AWS Load Balancer Controller
  - ExternalDNS
  - サンプルアプリケーション

##### 2.1. ArgoCD のインストール
```bash
# Helm リポジトリの追加
helm repo add argo https://argoproj.github.io/argo-helm

# ArgoCD のインストール
helm install -n argocd argocd argo/argo-cd --create-namespace
```

##### 2.2. App of Apps パターンの適用
```bash
# Blue 環境用のアプリケーション群をデプロイ
kubectl apply -f system/assets/argocd/app-of-apps-blue.yaml
```

**デプロイ確認:**
```bash
# ArgoCD アプリケーションの状態確認
argocd app get app-of-apps

# 期待される出力例:
# Name:               argocd/app-of-apps
# Project:            default
# Server:             https://kubernetes.default.svc
# Namespace:          argocd
# Sync Status:        Synced to HEAD
# Health Status:      Healthy
```

#### 3. Green EKS クラスター（新バージョン環境）のデプロイ

```bash
cd system/green-cluster
terraform init
terraform plan
terraform apply
```

**Blue 環境との違い:**
- EKS バージョン: 1.33（Blue は 1.32）
- 同一のドメインでIngressをデプロイ
- Route53 レコード ID: "test-green"（Blue は "test-blue"）
- 初期トラフィック重み: Green 30% / Blue 70%

##### 3.1. Green 環境への ArgoCD インストール
```bash
# Green クラスターに kubectl コンテキストを切り替え
kubectl config use-context <green-cluster-context>

# ArgoCD のインストール
helm repo add argo https://argoproj.github.io/argo-helm
helm install -n argocd argocd argo/argo-cd --create-namespace
```

##### 3.2. Green 環境用アプリケーションのデプロイ
```bash
kubectl apply -f system/assets/argocd/app-of-apps-green.yaml
```

この時点で、ExternalDNS により Route53 に以下のレコードが自動作成されます：
- Blue 環境: レコード ID "test-blue" （重み: 70）
- Green 環境: レコード ID "test-green" （重み: 30）

#### 4. Blue-Green 切り替えプロセス

Blue-Green デプロイメントの最も重要な段階です。段階的にトラフィックを移行し、安全にアップグレードを完了します。

##### 4.1. 両環境の稼働確認
```bash
# 両クラスターでアプリケーションが正常稼働していることを確認
# 期間: 数時間〜数日（要件に応じて調整）

# Green 環境の監視項目:
# - アプリケーションの応答性
# - ログの出力状況
# - メトリクスの正常性
# - リソース使用量
```

##### 4.2. Blue 環境のトラフィック重みを 0 に変更
```bash
# Blue 環境の Ingress 設定を編集
# system/assets/sample-app/overlays/blue/ingress-patch.yaml 内の
# .metadata.annotation.external-dns.alpha.kubernetes.io/aws-weight を 0 に変更

# Ingress の再作成（ArgoCD が自動的に再デプロイ）
kubectl delete ingress <ingress-name> -n <namespace>
# ArgoCD が自動的に再作成
```

##### 4.3. Route53 レコードの更新
```bash
# Blue 環境のレコードを削除（ExternalDNS が重み 0 で再作成）
aws route53 change-resource-record-sets \
  --hosted-zone-id <your-hosted-zone-id> \
  --change-batch '{
    "Changes": [
      {
        "Action": "DELETE",
        "ResourceRecordSet": {
          "Name": "your-domain.com",
          "Type": "A",
          "SetIdentifier": "test-blue",
          ...
        }
      }
    ]
  }'
```

##### 4.4. Green 環境のトラフィック重みを 100 に変更
```bash
# Green 環境の Ingress 設定を編集
# system/assets/sample-app/overlays/green/ingress-patch.yaml 内の
# .metadata.annotation.external-dns.alpha.kubernetes.io/aws-weight を 100 に変更

# 同様に Green 環境のレコードを削除・再作成
```

##### 4.5. Blue 環境の削除
```bash
# 全トラフィックが Green に移行し、安定稼働を確認後

# ArgoCD から Blue 環境のアプリケーションを削除
kubectl port-forward service/argocd-server -n argocd 8080:443 &

# ArgoCD admin パスワードの取得
ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

# ArgoCD にログイン
argocd login localhost:8080 --username admin --password $ARGO_PASSWORD

# App of Apps の削除
argocd app delete app-of-apps

# Blue クラスターの削除
cd system/blue-cluster
terraform destroy
```

### 🎉 アップグレード完了

これで EKS クラスターのバージョンアップグレードが完了しました！

**確認事項:**
- ✅ 全トラフィックが Green 環境（EKS 1.33）に流れている
- ✅ アプリケーションが正常稼働している  
- ✅ Blue 環境（EKS 1.32）が正常に削除された
- ✅ Route53 レコードが Green 環境のみになっている

## 🚨 トラブルシューティング

### よくある問題と解決方法

#### 1. ArgoCD アプリケーションが Sync されない
```bash
# 症状: ArgoCD アプリケーションが OutOfSync 状態
# 原因: GitHub リポジトリ URL の設定ミス

# 解決方法:
# 1. GitHubリポジトリURLを正しく設定
# 2. ArgoCD アプリケーションを手動で Sync
argocd app sync app-of-apps
```

#### 2. Pod Identity の権限エラー
```bash
# 症状: AWS Load Balancer Controller や ExternalDNS で権限エラー
# 原因: Pod Identity の設定ミスまたは IAM ロールの権限不足

# 確認方法:
kubectl describe pod <pod-name> -n <namespace>

# 解決方法:
# 1. Pod Identity Association を確認
aws eks describe-pod-identity-association \
  --cluster-name <cluster-name> \
  --association-id <association-id>

# 2. IAM ロールの権限を確認
aws iam get-role-policy --role-name <role-name> --policy-name <policy-name>
```

#### 3. Route53 レコードが作成されない
```bash
# 症状: ExternalDNS がRoute53にレコードを作成しない
# 原因: ExternalDNS の設定またはドメイン設定の問題

# 確認方法:
kubectl logs -l app.kubernetes.io/name=external-dns -n external-dns

# 解決方法:
# 1. ホストゾーンの設定を確認
aws route53 list-hosted-zones

# 2. ExternalDNS の設定を確認
kubectl get configmap external-dns -n external-dns -o yaml
```

#### 4. Terraform State のロック
```bash
# 症状: "state lock" エラーで terraform apply が実行できない
# 原因: 前回の実行が異常終了してロックが残っている

# 解決方法:
terraform force-unlock <lock-id>
```

## 🔧 カスタマイズとベストプラクティス

### 環境に応じたカスタマイズ

#### 1. クラスターサイズの調整
```hcl
# system/blue-cluster/main.tf または system/green-cluster/main.tf
module "eks" {
  source = "../../modules/cluster"
  
  cluster_name = "blue-cluster"
  cluster_version = "1.32"
  
  # 本番環境では以下を調整
  min_size = 3          # 最小ノード数
  max_size = 10         # 最大ノード数  
  desired_size = 5      # 希望ノード数
  instance_types = ["m5.large", "m5.xlarge"]  # インスタンスタイプ
}
```

#### 2. モニタリングの追加
```yaml
# system/assets/argocd/base/ に追加
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  namespace: argocd
spec:
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: "45.7.1"
```

#### 3. セキュリティ強化
```hcl
# system/common/network/main.tf
# VPC エンドポイントの追加例
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  
  route_table_ids = [aws_route_table.private.id]
}
```

### 運用のベストプラクティス

#### 1. デプロイメント前のチェックリスト
- [ ] 全ての GitHub リポジトリ URL が正しく設定されている
- [ ] Backend S3 バケットが作成済み
- [ ] Route53 ドメインが設定済み
- [ ] AWS 認証情報が正しく設定されている
- [ ] 必要な CLI ツールがインストール済み

#### 2. 切り替え時の監視項目
- [ ] アプリケーションのレスポンス時間
- [ ] エラー率の変化
- [ ] リソース使用量（CPU、メモリ）
- [ ] ネットワーク通信の状況
- [ ] ログの出力状況

#### 3. ロールバック戦略
```bash
# 緊急時のロールバック手順
# 1. トラフィック重みを即座に元に戻す
# 2. 問題のある Green 環境を隔離
# 3. Blue 環境の復旧（必要に応じて）
```

## 📚 参考資料

### 公式ドキュメント
- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/en/stable/)

### 関連記事
- [EKS Pod Identity を活用して Terraform でプロビジョニングした EKS を Blue/Green アップグレードしてみた](https://dev.classmethod.jp/articles/eks-pod-identity-terraform-blue-green-upgrade/)
- [AWS CodeBuild入門：セキュアなCIをTerraformで構築したよ](https://zenn.dev/junya0530/articles/8f3494d0ee8beb)
- [VPC エンドポイントを消すだけでセキュリティそのままにコストが節約できた](https://zenn.dev/simpleform_blog/articles/f048edb9efd2b2)

## 🤝 コントリビューション

本リポジトリへの改善提案やバグ報告は Issue または Pull Request でお気軽にお寄せください。

### 開発環境のセットアップ
```bash
# リポジトリのクローン
git clone https://github.com/jnytnai0613/blue-green-upgrade-blueprints.git
cd blue-green-upgrade-blueprints

# pre-commit の設定
pip install pre-commit
pre-commit install
```

## 📄 ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。詳細は [LICENSE](LICENSE) ファイルを参照してください。
