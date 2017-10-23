#docker run --rm -it -e VAULT_ADDR='http://127.0.0.1:8200' --privileged --network=host vault unseal $KEY
data "aws_availability_zones" "available" {}

data "aws_vpc" "vpc" {
  id = "${var.vpc_id}"
}

data "aws_route53_zone" "zone" {
  name = "${var.dns_zone}"
}

data "aws_acm_certificate" "cert" {
  domain = "${replace(var.dns_zone, "/.$/","")}" # dirty hack to strip off trailing dot
}

data "template_file" "vault" {
  template = "${file("${path.module}/files/vault.json")}"

  vars {
    datacenter            = "${data.aws_vpc.vpc.tags["Name"]}"
    env                   = "${var.env}"
    image                 = "${var.vault_image}"
    unseal_key0           = "${var.unseal_keys[0]}"
    unseal_key1           = "${var.unseal_keys[1]}"
    unseal_key2           = "${var.unseal_keys[2]}"
    awslogs_group         = "vault-${var.env}"
    awslogs_stream_prefix = "vault-${var.env}"
    awslogs_region        = "${var.region}"
  }
}

# End Data block

resource "aws_ecs_task_definition" "vault" {
  family                = "vault-${var.env}"
  container_definitions = "${data.template_file.vault.rendered}"
  network_mode          = "host"
  task_role_arn         = "${aws_iam_role.vault_task.arn}"

  #volume {
  #  name      = "docker-sock"
  #  host_path = "/var/run/docker.sock"
  #}
}

resource "aws_cloudwatch_log_group" "vault" {
  name = "${aws_ecs_task_definition.vault.family}"

  tags {
    VPC         = "${data.aws_vpc.vpc.tags["Name"]}"
    Application = "${aws_ecs_task_definition.vault.family}"
  }
}

resource "aws_ecs_service" "vault" {
  name            = "vault-${var.env}"
  cluster         = "${var.ecs_cluster_id}"
  task_definition = "${aws_ecs_task_definition.vault.arn}"
  desired_count   = "${var.desired_count}"

  placement_constraints {
    type = "distinctInstance"
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.vault_ui.arn}"

    #elb_name         = "${aws_elb.vault.name}"
    container_name = "vault-${var.env}"
    container_port = 8200
  }

  iam_role = "${aws_iam_role.ecsServiceRole.arn}"

  depends_on = ["aws_alb_target_group.vault_ui",
    "aws_alb_listener.vault_https",
    "aws_alb.vault",
    "aws_iam_role.ecsServiceRole",
  ]
}

# Security Groups
resource "aws_security_group" "lb-vault-sg" {
  name        = "tf-${data.aws_vpc.vpc.tags["Name"]}-vault-uiSecurityGroup"
  description = "Allow Web Traffic into the ${data.aws_vpc.vpc.tags["Name"]} VPC"
  vpc_id      = "${data.aws_vpc.vpc.id}"

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

  tags {
    Name        = "tf-${data.aws_vpc.vpc.tags["Name"]}-vault-uiSecurityGroup"
    Environment = "${var.env}"
  }
}
