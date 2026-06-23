output "app_url" {
  description = "URL of the load-balanced app (first request after launch may take ~15-20 min while the model pulls)"
  value       = "http://${aws_lb.app.dns_name}"
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "security_group_app" {
  value = aws_security_group.app.id
}
