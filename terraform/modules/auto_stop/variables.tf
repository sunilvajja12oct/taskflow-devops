variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "schedule_expression" {
  description = "EventBridge cron/rate expression for the nightly stop"
  type        = string
  default     = "cron(0 6 * * ? *)" # 06:00 UTC daily - overnight for US timezones
}
