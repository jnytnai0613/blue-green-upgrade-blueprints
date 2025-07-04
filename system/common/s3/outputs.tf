output "s3_bucketname_arn" {
  value       = aws_s3_bucket.terraform_state.arn
  description = "The arn of the S3 bucket"
}
