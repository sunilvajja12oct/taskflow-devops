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

variable "ssh_public_key_override" {
  description = "Set via TF_VAR_ssh_public_key_override in CI. Empty locally, falls back to reading your local key file."
  type        = string
  default     = ""
}
