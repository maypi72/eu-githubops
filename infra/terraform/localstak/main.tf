#################################
# S3 buckets
#################################
resource "aws_s3_bucket" "bck_listmonk_pg" {
  bucket = "bck-listmonk-pg"
}