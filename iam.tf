data "aws_iam_policy_document" "assume_role_vault_task" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vault_task" {
  path               = var.iam_path
  assume_role_policy = data.aws_iam_policy_document.assume_role_vault_task.json
}

# ecsServiceRole for vault

resource "aws_iam_role" "ecsServiceRole" {
  path = var.iam_path

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
      "Service": ["ecs.amazonaws.com"]

    },
    "Effect": "Allow",
    "Sid": ""
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "attach-ecsServiceRole" {
  role       = aws_iam_role.ecsServiceRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}
