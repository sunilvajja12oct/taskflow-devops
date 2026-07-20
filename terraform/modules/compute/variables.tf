variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "project" {
  type    = string
  default = "taskflow"
}

variable "instance_type" {
  description = "Must be on the account's free-tier-eligible list: t3.micro, t3.small, t4g.micro, t4g.small"
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_key" {
  description = "SSH public key auto-injected into ec2-user's authorized_keys at launch"
  type        = string
}
