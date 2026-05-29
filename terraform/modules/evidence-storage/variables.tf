variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "github_org" {
  description = "GitHub organization — used for resource naming/tagging"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name — used for resource naming/tagging"
  type        = string
}
