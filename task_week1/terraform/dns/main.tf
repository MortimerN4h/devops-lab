# Route53 hosted zone for a domain bought at an EXTERNAL registrar.
#
# Kept in its own folder ON PURPOSE: the zone gets 4 random AWS nameservers, and you copy them
# to the registrar once. If the zone lived with the EC2 code, every destroy/apply would create
# a NEW zone with DIFFERENT nameservers and the domain would stop working.
# Cost: $0.50/month per zone -> create once, keep it.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Route53 is global; the region only matters for the API endpoint
}

resource "aws_route53_zone" "main" {
  name = var.domain_name
}
