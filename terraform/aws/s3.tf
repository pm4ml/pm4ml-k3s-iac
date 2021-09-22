resource "aws_s3_bucket" "longhorn_backups" {
  bucket = "${local.base_domain}-lhbck"
  acl    = "private"
  tags = merge({ Name = "${local.name}-longhorn_backups" }, local.common_tags)
}

resource "aws_iam_user" "longhorn_backups" {
  name = "${local.base_domain}-lhbck"
  tags = merge({ Name = "${local.name}-longhorn_backups" }, local.common_tags)
}
resource "aws_iam_access_key" "longhorn_backups" {
  user = aws_iam_user.longhorn_backups.name
}
# IAM Policy to allow longhorn store objects
resource "aws_iam_user_policy" "longhorn_backups" {
  name = "${local.base_domain}-lhbck"
  user = aws_iam_user.longhorn_backups.name

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "GrantLonghornBackupstoreAccess0",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::${local.base_domain}-lhbck",
                "arn:aws:s3:::${local.base_domain}-lhbck/*"
            ]
        }
    ]
}
EOF
}
