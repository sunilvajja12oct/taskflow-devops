output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "instance_ids" {
  value = module.compute.instance_ids
}

output "ansible_bucket_name" {
  value = module.compute.ansible_bucket_name
}

output "secret_arn" {
  value = module.secrets.secret_arn
}

output "rotation_lambda_name" {
  value = module.secrets.rotation_lambda_name
}

output "ecr_url" {
  value = module.registry.repository_url
}

output "github_actions_role_arn" {
  value = module.cicd.role_arn
}
