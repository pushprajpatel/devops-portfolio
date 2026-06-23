variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "EC2 instance type. Needs >=8GB RAM to run the qwen2.5:7b model comfortably."
  type        = string
  default     = "t3.large"
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH access. Leave null to disable SSH key access."
  type        = string
  default     = null
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into instances (e.g. \"YOUR_IP/32\"). Never leave this as 0.0.0.0/0."
  type        = string
  default     = "0.0.0.0/0"
}

variable "github_repo_url" {
  description = "Git URL the instance clones on boot to run the app"
  type        = string
  default     = "https://github.com/pushprajpatel/devops-portfolio.git"
}

variable "asg_min_size" {
  description = "Minimum number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in the Auto Scaling Group"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
}
