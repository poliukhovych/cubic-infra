output "public_ip" {
  value = aws_eip.cubic.public_ip
}

output "url" {
  value = var.domain == "" ? "http://${aws_eip.cubic.public_ip}" : "https://${var.domain}"
}

output "ssh" {
  value = var.ssh_public_key == "" ? null : "ssh ubuntu@${aws_eip.cubic.public_ip}"
}
