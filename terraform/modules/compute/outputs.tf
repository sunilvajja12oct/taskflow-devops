output "instance_ids" {
  value = [aws_instance.app.id]
}

output "instance_private_ips" {
  value = [aws_instance.app.private_ip]
}

output "ansible_bucket_name" {
  value = aws_s3_bucket.ansible_transfer.bucket
}
