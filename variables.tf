# Authored by Antoine CICHOWICZ | Github: Yris Ops
# Copyright: Apache License 2.0

variable "region" {
  type        = string
  description = "AWS region"
}

variable "PublicSubnetA" {
  type        = string
  description = "Public Subnet A"
}

variable "PublicSubnetB" {
  type        = string
  description = "Public Subnet B"
}

variable "PrivateSubnetA" {
  type        = string
  description = "Private Subnet A"
}

variable "PrivateSubnetB" {
  type        = string
  description = "Private Subnet B"
}

variable "InternetGateway" {
  type        = string
  description = "Internet Gateway"
}

variable "VPC" {
  type        = string
  description = "VPC Id"
}

variable "EC2InstanceType" {
  type        = string
  description      = "EC2 instance type"
}

variable "EC2InstanceProfile" {
  type        = string
  description = "Instance profile for Systems Manager"
}

variable "policy_name" {
  type        = string
  description = "Policy Name"
}

variable "key_pair_name" {
  type        = string
  description = "Key Pair name"
}

variable "AMI" {
  type        = string
  description = "Amazon Machine Image (AMI) ID"
}

variable "encrypted_password" {
  type        = string
  description = "Encrypted GLPI password"
  default     = "MySuperGlpi2022"
}

variable "bucket_name" {
  type        = string
  description = "Bucket Name"
}

variable "multi_az" {
  type        = bool
  description      = "Multi AZ"
  default          = true
}