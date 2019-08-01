variable "name" {}
variable "environment" {}
variable "ssh_key_name" {}
variable "ssh_key_file" {}
variable "region" {}
variable "vpc_cidr" {}
variable "chef_server_url" {}
variable "chef_server_user_key" {}
variable "chef_server_user_name" {}
variable "chef_version" {}
variable "ami_id" {}
variable "chef_runlist" {
     type = "list"
}