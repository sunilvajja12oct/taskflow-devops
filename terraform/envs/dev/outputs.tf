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
