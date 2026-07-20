output "secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "kms_key_arn" {
  value = aws_kms_key.secrets.arn
}

output "rotation_lambda_name" {
  value = aws_lambda_function.rotate_secret.function_name
}

output "ops_alerts_topic_arn" {
  value = aws_sns_topic.ops_alerts.arn
}
