data "archive_file" "auto_stop_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/auto_stop.py"
  output_path = "${path.module}/lambda/auto_stop.zip"
}

resource "aws_iam_role" "auto_stop_lambda" {
  name = "${var.project}-${var.environment}-auto-stop-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "auto_stop_lambda" {
  name = "auto-stop-policy"
  role = aws_iam_role.auto_stop_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:StopInstances"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Name" = [
              "${var.project}-${var.environment}-app-01",
              "${var.project}-${var.environment}-nat",
            ]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "auto_stop" {
  function_name    = "${var.project}-${var.environment}-auto-stop"
  role             = aws_iam_role.auto_stop_lambda.arn
  handler          = "auto_stop.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.auto_stop_lambda.output_path
  source_code_hash = data.archive_file.auto_stop_lambda.output_base64sha256

  environment {
    variables = {
      APP_TAG_NAME = "${var.project}-${var.environment}-app-01"
      NAT_TAG_NAME = "${var.project}-${var.environment}-nat"
    }
  }
}

resource "aws_cloudwatch_event_rule" "auto_stop_schedule" {
  name                = "${var.project}-${var.environment}-auto-stop-schedule"
  description         = "Nightly off-hours stop of the app+NAT instances to save cost"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "auto_stop" {
  rule = aws_cloudwatch_event_rule.auto_stop_schedule.name
  arn  = aws_lambda_function.auto_stop.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.auto_stop_schedule.arn
}
