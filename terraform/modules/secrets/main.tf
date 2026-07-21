resource "aws_kms_key" "secrets" {
  description             = "Customer-managed key for ${var.project}-${var.environment} secrets"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project}-${var.environment}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project}/${var.environment}/db-credentials"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 0 # disposable dev infra - let destroy-all.sh -> up.sh recreate this immediately, no soft-delete window blocking the next apply
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "taskflow_app"
    password = "changeme-placeholder-rotated-on-first-run"
  })

  lifecycle {
    ignore_changes = [secret_string] # the rotation Lambda owns this value after first apply
  }
}

data "archive_file" "rotation_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/rotate_secret.py"
  output_path = "${path.module}/lambda/rotate_secret.zip"
}

resource "aws_iam_role" "rotation_lambda" {
  name = "${var.project}-${var.environment}-secret-rotation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "rotation_lambda" {
  name = "secrets-rotation-policy"
  role = aws_iam_role.rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.secrets.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "rotate_secret" {
  function_name    = "${var.project}-${var.environment}-secret-rotation"
  role             = aws_iam_role.rotation_lambda.arn
  handler          = "rotate_secret.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.rotation_lambda.output_path
  source_code_hash = data.archive_file.rotation_lambda.output_base64sha256
}

resource "aws_lambda_permission" "allow_secrets_manager" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotate_secret.function_name
  principal     = "secretsmanager.amazonaws.com"
}

resource "aws_secretsmanager_secret_rotation" "db_credentials" {
  secret_id           = aws_secretsmanager_secret.db_credentials.id
  rotation_lambda_arn = aws_lambda_function.rotate_secret.arn

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [aws_lambda_permission.allow_secrets_manager]
}
