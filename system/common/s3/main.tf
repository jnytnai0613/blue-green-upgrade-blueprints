resource "aws_s3_bucket" "terraform_state" {
  bucket = "eks-cluster-state-taniai"

  # 謝ってS3バケットを削除するのを防止
  lifecycle {
    prevent_destroy = true
  }
}

# State fileの完全な履歴が見れるようにバージョニングを有効化
resource "aws_s3_bucket_versioning" "enabled" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# デフォルトでServer-Sideで暗号化を有効化
resource "aws_s3_bucket_server_side_encryption_configuration" "default" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 明示的にこのS3バケットに対する全パブリックアクセスをブロック
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

/*
# v1.0からuse_lockfileが実装されて、DynamoDB不要になった
# https://github.com/hashicorp/terraform/pull/35661
resource "aws_dynamodb_table" "terraform-locks" {
  name = "terraform-up-and-runnnig-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
*/
