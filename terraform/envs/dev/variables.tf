variable "aws_region" {
  default = "us-east-1"
}

variable "environment" {
  default = "dev"
}

variable "owner" {
  description = "Your name/handle, used in resource tags"
  type        = string
  default     = "sunil"
}
