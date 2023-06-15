module "bucket_one" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.13.0"

  bucket = "acg-aws-misterwalker-co-uk-one1"

  lifecycle_rule = [{
    id      = "lifecycle"
    enabled = true

    expiration = {
      days                         = 7
      expired_object_delete_marker = true
    }
  }]

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }

    # Block deletion of non-empty bucket
    force_destroy = false

    # S3 bucket-level Public Access Block configuration
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true

    # S3 Bucket Ownership Controls
    control_object_ownership = true
    object_ownership         = "BucketOwnerEnforced"

  }
}

module "bucket_two" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.13.0"

  bucket = "acg-aws-misterwalker-co-uk-two2"

  lifecycle_rule = [{
    id      = "lifecycle"
    enabled = true

    expiration = {
      days                         = 7
      expired_object_delete_marker = true
    }
  }]

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }

    # Block deletion of non-empty bucket
    force_destroy = false

    # S3 bucket-level Public Access Block configuration
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true

    # S3 Bucket Ownership Controls
    control_object_ownership = true
    object_ownership         = "BucketOwnerEnforced"

  }
}
