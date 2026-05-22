output "inference_ip" {
  description = "Private IP of inference VM"
  value       = aws_instance.inference_vm.private_ip
}

output "caller_ip" {
  description = "Private IP of caller VM"
  value       = aws_instance.caller_vm.private_ip
}

output "api_ip" {
  description = "Public IP of API gateway VM"
  value       = aws_instance.api_vm.public_ip
}

