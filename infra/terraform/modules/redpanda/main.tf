variable "cluster_name" {
  type = string
}

variable "broker_count" {
  type    = number
  default = 3
}

variable "instance_type" {
  type    = string
  default = "im4gn.xlarge"
}

variable "environment" {
  type = string
}

resource "aws_s3_bucket" "tiered" {
  bucket = "${var.cluster_name}-redpanda-tiered"
  tags   = { Environment = var.environment }
}

resource "aws_s3_bucket_versioning" "tiered" {
  bucket = aws_s3_bucket.tiered.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tiered" {
  bucket = aws_s3_bucket.tiered.id

  rule {
    id     = "archive-old-segments"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
  }
}

resource "aws_iam_role" "redpanda" {
  name = "${var.cluster_name}-redpanda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Environment = var.environment }
}

resource "aws_iam_role_policy" "redpanda_s3" {
  name = "redpanda-tiered-storage"
  role = aws_iam_role.redpanda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
      ]
      Resource = [
        aws_s3_bucket.tiered.arn,
        "${aws_s3_bucket.tiered.arn}/*",
      ]
    }]
  })
}

output "tiered_storage_bucket" {
  value = aws_s3_bucket.tiered.bucket
}

output "redpanda_role_arn" {
  value = aws_iam_role.redpanda.arn
}

output "broker_count" {
  value = var.broker_count
}
