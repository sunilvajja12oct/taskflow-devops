module "network" {
  source = "../../modules/network"

  environment          = var.environment
  project              = "taskflow"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  azs                  = ["us-east-1a", "us-east-1b"]
}

module "compute" {
  instance_type  = "t3.small"
  ssh_public_key = file(pathexpand("~/.ssh/taskflow-ansible.pub"))
  source         = "../../modules/compute"

  vpc_id              = module.network.vpc_id
  private_subnet_ids  = module.network.private_subnet_ids
  security_group_id   = module.network.private_instances_sg_id
  environment         = var.environment
  project             = "taskflow"
  alarm_sns_topic_arn = module.secrets.ops_alerts_topic_arn
}

module "secrets" {
  alert_email = "sunilvajja12oct@gmail.com"
  source      = "../../modules/secrets"

  environment = var.environment
  project     = "taskflow"
}

module "registry" {
  source      = "../../modules/registry"
  environment = var.environment
}

module "cicd" {
  source      = "../../modules/cicd"
  environment = var.environment
  github_repo = "sunilvajja12oct/taskflow-devops"
}
