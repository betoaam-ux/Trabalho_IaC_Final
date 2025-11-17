#############################
# Outputs
#############################

output "alb_dns_name" {
  value       = aws_lb.alb.dns_name
}

output "target_group_arn" {
  value       = aws_lb_target_group.tg.arn
}

output "autoscaling_group_name" {
  value       = aws_autoscaling_group.asg.name
}

output "vpc_id" {
  value       = aws_vpc.main.id
}

output "public_subnet_a" {
  value       = aws_subnet.public_a.id
}

output "public_subnet_b" {
  value       = aws_subnet.public_b.id
}

output "security_group_id" {
  value       = aws_security_group.web_sg.id
}
