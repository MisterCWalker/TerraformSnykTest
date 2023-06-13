data "aws_caller_identity" "current" {}
locals {
  domain_name = "acg.aws.misterwalker.co.uk"
  subdomain   = "api"
  account_id  = data.aws_caller_identity.current.account_id
}

###################
# REST API Gateway
###################
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "test-rest-api"
  description = "Test REST API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "test-request"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.my_lambda.invoke_arn
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:us-east-1:${local.account_id}:${aws_api_gateway_rest_api.api_gateway.id}/*/${aws_api_gateway_method.method.http_method}${aws_api_gateway_resource.resource.path}"
}

resource "aws_api_gateway_domain_name" "domain" {
  regional_certificate_arn = module.acm.acm_certificate_arn
  domain_name              = local.domain_name

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on  = [aws_api_gateway_integration.integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage" {
  stage_name    = "dev"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  deployment_id = aws_api_gateway_deployment.deployment.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.rest_api_gateway.arn
    format          = "$context.identity.sourceIp - - [$context.requestTime] \"$context.httpMethod $context.routeKey $context.protocol\" $context.status $context.responseLength $context.requestId $context.integrationErrorMessage"
  }

  xray_tracing_enabled = true
}

resource "aws_api_gateway_base_path_mapping" "mapping" {
  api_id      = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = aws_api_gateway_stage.stage.stage_name
  domain_name = aws_api_gateway_domain_name.domain.domain_name
}

######
# ACM
######

resource "aws_route53_zone" "zone" {
  name = local.domain_name
}

resource "aws_route53_record" "ns" {
  allow_overwrite = true
  name            = local.domain_name
  ttl             = 172800
  type            = "NS"
  zone_id         = aws_route53_zone.zone.zone_id

  records = [
    "ns-1620.awsdns-10.co.uk",
    "ns-489.awsdns-61.com",
    "ns-1134.awsdns-13.org",
    "ns-552.awsdns-05.net"
  ]
}

resource "aws_route53_record" "soa" {
  allow_overwrite = true
  name            = local.domain_name
  ttl             = 900
  type            = "SOA"
  zone_id         = aws_route53_zone.zone.zone_id

  records = ["ns-1620.awsdns-10.co.uk. awsdns-hostmaster.amazon.com. 1 7200 900 1209600 86400"]

}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 3.0"

  domain_name               = local.domain_name
  zone_id                   = aws_route53_zone.zone.id
  subject_alternative_names = ["${local.subdomain}.${local.domain_name}"]
}

##########
# Route53
##########

resource "aws_route53_record" "api_rest" {
  zone_id = aws_route53_zone.zone.zone_id
  name    = "${local.subdomain}.${local.domain_name}"
  type    = "A"

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.domain.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.domain.regional_zone_id
  }
}

#############
# CloudWatch
#############

resource "aws_cloudwatch_log_group" "rest_api_gateway" {
  name              = "/aws/apigateway/test-rest-api"
  retention_in_days = 7
}

resource "aws_iam_role" "api_gw_cloudwatch_role" {
  name = "api_gw_cloudwatch_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "api_gw_cloudwatch_policy" {
  name = "default"
  role = aws_iam_role.api_gw_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_api_gateway_account" "api_gw_account" {
  cloudwatch_role_arn = aws_iam_role.api_gw_cloudwatch_role.arn
}
