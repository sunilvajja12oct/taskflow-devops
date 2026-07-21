data "aws_caller_identity" "current" {}

# Always resolves to the newest Amazon Linux 2023 AMI at apply time -
# no hardcoded, eventually-stale AMI ID to maintain.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project}-${var.environment}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project}-${var.environment}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name

  metadata_options {
    http_tokens = "required" # IMDSv2 only - blocks the classic SSRF-to-credentials attack path
  }

  # First-boot bootstrap: SSH key + a working k3s/Helm node, so the CI
  # deploy job never has to wait on a manual Ansible run to get a fresh
  # instance ready. Ansible (roles: common-hardening, cloudwatch-agent,
  # webserver) remains the path for everything that isn't on this
  # critical path - run it by hand after boot for those.
  user_data = <<-EOF
    #!/bin/bash
    set -e
    mkdir -p /home/ec2-user/.ssh
    echo "${var.ssh_public_key}" >> /home/ec2-user/.ssh/authorized_keys
    chown -R ec2-user:ec2-user /home/ec2-user/.ssh
    chmod 700 /home/ec2-user/.ssh
    chmod 600 /home/ec2-user/.ssh/authorized_keys

    mkdir -p /opt/taskflow

    # Retry on the binary showing up, not curl's exit code: outbound
    # internet through the NAT instance (a separate ASG created in the
    # same apply) isn't always routable this early in boot, and a failed
    # curl piped into `sh -`/`bash` still exits 0 - `sh` with no stdin is
    # a no-op, not an error - so trusting the pipe's exit status would
    # silently skip the install.
    for i in $(seq 1 30); do
      [ -f /usr/local/bin/k3s ] && break
      curl -sfL https://get.k3s.io | sh - || true
      sleep 10
    done

    for i in $(seq 1 30); do
      k3s kubectl get nodes 2>/dev/null | grep -q Ready && break
      sleep 10
    done

    k3s kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml || true
    k3s kubectl patch deployment metrics-server -n kube-system --type=json \
      -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || true

    for i in $(seq 1 30); do
      [ -f /usr/local/bin/helm ] && break
      curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash || true
      sleep 10
    done

    mkdir -p /home/ec2-user/taskflow-chart
    chown ec2-user:ec2-user /home/ec2-user/taskflow-chart

    # Only claim done once both binaries are actually there - CI's deploy
    # job trusts this marker before running helm upgrade.
    if [ -f /usr/local/bin/k3s ] && [ -f /usr/local/bin/helm ]; then
      touch /opt/taskflow/bootstrap-complete
    fi
  EOF

  tags = {
    Name = "${var.project}-${var.environment}-app-01"
    Role = "webserver"
  }
}

# Relay bucket: CI syncs the Helm chart here after `apply`, and the
# instance pulls from it in the `deploy` job (see aws_iam_role_policy
# .ansible_transfer_read below) instead of depending on a manual Ansible
# run to have copied the chart over. 1-day expiry - not a data store.
resource "aws_s3_bucket" "ansible_transfer" {
  bucket = "${var.project}-${var.environment}-ansible-ssm-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "ansible_transfer" {
  bucket                  = aws_s3_bucket.ansible_transfer.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "ansible_transfer" {
  bucket = aws_s3_bucket.ansible_transfer.id
  rule {
    id     = "expire-transfer-files"
    status = "Enabled"
    filter {}
    expiration {
      days = 1
    }
  }
}
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Lets the instance pull the Helm chart CI syncs into ansible_transfer,
# so `deploy` doesn't depend on an Ansible run having copied it there.
resource "aws_iam_role_policy" "ansible_transfer_read" {
  name = "${var.project}-${var.environment}-ansible-transfer-read"
  role = aws_iam_role.ec2_ssm.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.ansible_transfer.arn, "${aws_s3_bucket.ansible_transfer.arn}/*"]
    }]
  })
}
