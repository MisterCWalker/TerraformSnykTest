data "aws_caller_identity" "current" {}
locals {
  domain_name = "cmcloudlab0626.info" #trimsuffix(data.aws_route53_zone.this.name, ".")
  walker_name = "acg.aws.misterwalker.co.uk"
  subdomain   = "complete-http"
  subrest     = "rest"
  account_id  = data.aws_caller_identity.current.account_id
}

###################
# HTTP API Gateway
###################

module "apigateway_v2" {
  source  = "terraform-aws-modules/apigateway-v2/aws"
  version = "2.2.2"

  name          = "dev-http"
  description   = "My awesome HTTP API Gateway"
  protocol_type = "HTTP"

  create_default_stage = true

  domain_name                 = local.domain_name
  domain_name_certificate_arn = module.acm.acm_certificate_arn

  default_stage_access_log_destination_arn = aws_cloudwatch_log_group.logs.arn
  default_stage_access_log_format          = "$context.identity.sourceIp - - [$context.requestTime] \"$context.httpMethod $context.routeKey $context.protocol\" $context.status $context.responseLength $context.requestId $context.integrationErrorMessage"

  default_route_settings = {
    detailed_metrics_enabled = true
    throttling_burst_limit   = 100
    throttling_rate_limit    = 100
  }

  # Routes and integrations
  integrations = {
    "$default" = {
      lambda_arn             = aws_lambda_function.my_lambda.arn
      integration_type       = "AWS_PROXY"
      payload_format_version = "2.0"
      timeout_milliseconds   = 30000
    }
  }

}

######
# ACM
######

data "aws_route53_zone" "this" {
  name = local.domain_name
}

data "aws_route53_zone" "mw" {
  name = local.walker_name
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 3.0"

  domain_name               = local.domain_name
  zone_id                   = data.aws_route53_zone.this.id
  subject_alternative_names = ["${local.subdomain}.${local.domain_name}"]
}

module "walker" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 3.0"

  domain_name               = local.walker_name
  zone_id                   = data.aws_route53_zone.mw.id
  subject_alternative_names = ["${local.subrest}.${local.walker_name}"]
}

##########
# Route53
##########

resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.subdomain
  type    = "A"

  alias {
    name                   = module.apigateway_v2.apigatewayv2_domain_name_configuration[0].target_domain_name
    zone_id                = module.apigateway_v2.apigatewayv2_domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api_rest" {
  zone_id = data.aws_route53_zone.mw.zone_id
  name    = local.subrest
  type    = "A"

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.domain.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.domain.cloudfront_zone_id
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # Source arn for API Gateway resource
  source_arn = "${module.apigateway_v2.apigatewayv2_api_execution_arn}/*/*"
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
  http_method   = "POST"
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
  certificate_arn = module.walker.acm_certificate_arn
  domain_name     = "local.walker_name"
}

resource "aws_cloudwatch_log_group" "rest_api_gateway" {
  name              = "/aws/apigateway/test-rest-api"
  retention_in_days = 7
}
