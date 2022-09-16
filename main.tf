#docker run --rm -it -e VAULT_ADDR='http://127.0.0.1:8200' --privileged --network=host vault unseal $KEY
data "aws_availability_zones" "available" {
}

data "aws_vpc" "vpc" {
  id = var.vpc_id
}

data "aws_route53_zone" "zone" {
  count = local.enable_custom_domain ? 1 : 0
  name  = var.dns_zone
}

data "aws_acm_certificate" "cert" {
  count       = local.enable_custom_domain ? 1 : 0
  domain      = trimsuffix(var.dns_zone, ".")

  statuses    = ["ISSUED"]
  most_recent = true
}

data "aws_region" "current" {
}

data "template_file" "vault" {
  template = file("${path.module}/files/vault.json")

  vars = {
    datacenter            = local.vpc_name
    env                   = var.env
    image                 = var.vault_image
    unseal_key0           = var.unseal_keys[0]
    unseal_key1           = var.unseal_keys[1]
    unseal_key2           = var.unseal_keys[2]
    awslogs_group         = "vault-${var.env}"
    awslogs_stream_prefix = "vault-${var.env}"
    awslogs_region        = data.aws_region.current.name
    vault_ui              = var.enable_vault_ui ? "true" : "false"
  }
}

data "template_file" "vault_init" {
  template = file("${path.module}/files/vault_init.json")

  vars = {
    datacenter            = local.vpc_name
    env                   = var.env
    image                 = var.vault_image
    awslogs_group         = "vault-${var.env}"
    awslogs_stream_prefix = "vault-${var.env}"
    awslogs_region        = data.aws_region.current.name
    vault_ui              = var.enable_vault_ui ? "true" : "false"
  }
}

# End Data block
# local variables
locals {
  initialize             = var.initialize ? true : false
  cluster_count          = length(var.ecs_cluster_ids)
  vault_standalone_count = local.initialize ? 0 : local.cluster_count == 1 ? 1 : 0
  vault_clustered_count  = local.initialize ? 0 : local.cluster_count > 1 ? 1 : 0
  vault_init_count       = local.initialize ? 1 : 0
  vpc_name               = data.aws_vpc.vpc.tags["Name"]
  sg_name                = "tf-${local.vpc_name}-vault-uiSecurityGroup"
  sg_tags = merge(
    var.tags,
    {
      "Name"        = local.sg_name
      "Environment" = var.env
    },
  )
  log_tags = merge(
    var.tags,
    {
      "VPC"         = local.vpc_name
      "Application" = aws_ecs_task_definition.vault.family
    },
  )
}

resource "aws_ecs_task_definition" "vault" {
  family                = "vault-${var.env}"
  container_definitions = data.template_file.vault.rendered
  network_mode          = "host"
  task_role_arn         = aws_iam_role.vault_task.arn
}

resource "aws_cloudwatch_log_group" "vault" {
  name              = aws_ecs_task_definition.vault.family
  retention_in_days = var.cloudwatch_log_retention
  tags              = local.log_tags
}

resource "aws_ecs_task_definition" "vault_init" {
  count                 = local.vault_init_count
  family                = "vault-init-${var.env}"
  container_definitions = data.template_file.vault_init.rendered
  network_mode          = "host"
  task_role_arn         = aws_iam_role.vault_task.arn
}

resource "aws_cloudwatch_log_group" "vault_init" {
  count             = local.vault_init_count
  name              = aws_ecs_task_definition.vault_init[0].family
  retention_in_days = "1"
  tags              = local.log_tags
}

# ECS Service
resource "aws_ecs_service" "vault" {
  /* count                              = "${local.cluster_count  == 1 ? 1 : 0}" */
  count                              = local.vault_standalone_count
  name                               = "vault-${var.env}"
  cluster                            = var.ecs_cluster_ids[0]
  task_definition                    = aws_ecs_task_definition.vault.arn
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.service_minimum_healthy_percent
  iam_role                           = aws_iam_role.ecsServiceRole.arn

  placement_constraints {
    type = "distinctInstance"
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.vault_ui.arn
    container_name   = "vault-${var.env}"
    container_port   = 8200
  }

  depends_on = [
    aws_alb_target_group.vault_ui,
    aws_alb_listener.vault_https,
    aws_alb.vault,
    aws_iam_role.ecsServiceRole,
  ]
}

resource "aws_ecs_service" "vault_primary" {
  /* count                              = "${local.cluster_count  > 1 ? 1 : 0}" */
  count                              = local.vault_clustered_count
  name                               = "vault-${var.env}-primary"
  cluster                            = var.ecs_cluster_ids[0]
  task_definition                    = aws_ecs_task_definition.vault.arn
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.service_minimum_healthy_percent
  iam_role                           = aws_iam_role.ecsServiceRole.arn

  placement_constraints {
    type = "distinctInstance"
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.vault_ui.arn
    container_name   = "vault-${var.env}"
    container_port   = 8200
  }

  depends_on = [
    aws_alb_target_group.vault_ui,
    aws_alb_listener.vault_https,
    aws_alb.vault,
    aws_iam_role.ecsServiceRole,
  ]
}

resource "aws_ecs_service" "vault_secondary" {
  /* count                              = "${local.cluster_count  > 1 ? 1 : 0}" */
  count                              = local.vault_clustered_count
  name                               = "vault-${var.env}-secondary"
  cluster                            = var.ecs_cluster_ids[1]
  task_definition                    = aws_ecs_task_definition.vault.arn
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.service_minimum_healthy_percent
  iam_role                           = aws_iam_role.ecsServiceRole.arn

  placement_constraints {
    type = "distinctInstance"
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.vault_ui.arn
    container_name   = "vault-${var.env}"
    container_port   = 8200
  }

  depends_on = [
    aws_alb_target_group.vault_ui,
    aws_alb_listener.vault_https,
    aws_alb.vault,
    aws_iam_role.ecsServiceRole,
  ]
}

resource "aws_ecs_service" "vault_init" {
  count                              = local.vault_init_count
  name                               = "vault-init-${var.env}"
  cluster                            = var.ecs_cluster_ids[0]
  task_definition                    = aws_ecs_task_definition.vault_init[0].arn
  desired_count                      = "1"
  deployment_minimum_healthy_percent = "0"

  placement_constraints {
    type = "distinctInstance"
  }
}

# End Service
# Security Groups
resource "aws_security_group" "lb-vault-sg" {
  name        = "tf-${local.vpc_name}-vault-uiSecurityGroup"
  description = "Allow Web Traffic into the ${local.vpc_name} VPC"
  vpc_id      = data.aws_vpc.vpc.id
  tags        = local.sg_tags

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
