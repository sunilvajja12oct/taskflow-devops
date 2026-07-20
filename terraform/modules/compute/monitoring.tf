variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN to notify on alarm (reuses the ops-alerts topic from the secrets module)"
  type        = string
}

resource "aws_cloudwatch_metric_alarm" "instance_status_check" {
  alarm_name          = "${var.project}-${var.environment}-app-status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Fires if the app instance fails an AWS status check"
  dimensions = {
    InstanceId = aws_instance.app.id
  }
  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
}
