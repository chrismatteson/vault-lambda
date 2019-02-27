provider "aws" {
  region = "${var.aws_region}"
}

# generate random project name
resource "random_id" "project_name" {
  byte_length = 4
}

resource "aws_kms_key" "vault" {
  description             = "${random_id.project_name.hex}-vault-unseal"
}

data "local_file" "lambda_function" {
    filename = "${path.module}/../lambda_function.py"
}

data "local_file" "vault_config" {
    filename = "${path.module}/../vault.hcl"
}

data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/vault_lambda.zip"

  source {
    content  = "${data.local_file.vault_config.content}"
    filename = "vault.hcl"
  }

  source {
    content  = "${data.local_file.lambda_function.content}"
    filename = "lambda_function.py"
  }
}

resource "null_resource" "download_vault" {
  provisioner "local-exec" {
    command = "curl ${var.vault_url} -o ${path.module}/vault.zip; unzip vault.zip"
  }
}

resource "aws_s3_bucket" "vaultdata" {
  bucket = "${random_id.project_name.hex}-vaultdata"
  acl    = "private"

  tags {
    Name        = "Vault Lambda"
  }
}

resource "aws_s3_bucket_object" "vault" {
  bucket = "${aws_s3_bucket.vaultdata.bucket}"
  key    = "vault"
  source = "${path.module}/vault"
#  etag   = "${md5(file(path.module/vault))}"
  depends_on = ["null_resource.download_vault"]
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "${random_id.project_name.hex}-iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "vault_policy" {
  name = "${random_id.project_name.hex}-vault-policy"
  role = "${aws_iam_role.iam_for_lambda.id}"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kms:ListKeys",
                "s3:PutAccountPublicAccessBlock",
                "s3:GetAccountPublicAccessBlock",
                "kms:GenerateRandom",
                "s3:ListAllMyBuckets",
                "kms:ListAliases",
                "kms:CreateKey",
                "s3:HeadBucket"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:*",
                "kms:*"
            ],
            "Resource": [
                "${aws_kms_key.vault.arn}",
                "arn:aws:s3:::${aws_s3_bucket.vaultdata.bucket}",
                "arn:aws:s3:::${aws_s3_bucket.vaultdata.bucket}/*"
            ]
        }
    ]
}
EOF
}

resource "aws_lambda_function" "vault_lambda" {
  filename         = "${data.archive_file.lambda.output_path}"
  function_name    = "${random_id.project_name.hex}-vault-lambda"
  role             = "${aws_iam_role.iam_for_lambda.arn}"
  handler          = "lambda_function.lambda_handler"
  source_code_hash = "${base64sha256(file("${data.archive_file.lambda.output_path}"))}"
  runtime          = "python2.7"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      BUCKET_NAME = "${aws_s3_bucket.vaultdata.bucket}"
      KEY_ID      = "${aws_kms_key.vault.id}"
    }
  }
}

resource "aws_cloudwatch_log_group" "vault" {
  name              = "/aws/lambda/${aws_lambda_function.vault_lambda.function_name}"
  retention_in_days = 14
}

# See also the following AWS managed policy: AWSLambdaBasicExecutionRole
resource "aws_iam_policy" "lambda_logging" {
  name = "${random_id.project_name.hex}-lambda_logging"
  path = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role = "${aws_iam_role.iam_for_lambda.name}"
  policy_arn = "${aws_iam_policy.lambda_logging.arn}"
}

resource "aws_api_gateway_rest_api" "vault" {
  name        = "${random_id.project_name.hex}-vault-gateway"
  description = "This is the API for Vault as a Lambda"
}

resource "aws_api_gateway_resource" "vault" {
  rest_api_id = "${aws_api_gateway_rest_api.vault.id}"
  parent_id   = "${aws_api_gateway_rest_api.vault.root_resource_id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "vault" {
  rest_api_id   = "${aws_api_gateway_rest_api.vault.id}"
  resource_id   = "${aws_api_gateway_resource.vault.id}"
  http_method   = "ANY"
  authorization = "NONE"
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "vault" {
  rest_api_id = "${aws_api_gateway_rest_api.vault.id}"
  resource_id = "${aws_api_gateway_resource.vault.id}"
  http_method = "${aws_api_gateway_method.vault.http_method}"
  type        = "MOCK"
}

resource "aws_api_gateway_deployment" "vault" {
  depends_on = ["aws_api_gateway_integration.vault"]

  rest_api_id = "${aws_api_gateway_rest_api.vault.id}"
  stage_name  = "test"

  variables = {
  }
}
