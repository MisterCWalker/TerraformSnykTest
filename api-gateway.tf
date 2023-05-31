# Module version of above
locals {
  domain_name = "cmcloudlab1681.info" #trimsuffix(data.aws_route53_zone.this.name, ".")
  subdomain   = "complete-http"
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
    throttling_burst_limit           = 100
    throttling_rate_limit        = 100
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

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 3.0"

  domain_name               = local.domain_name
  zone_id                   = data.aws_route53_zone.this.id
  subject_alternative_names = ["${local.subdomain}.${local.domain_name}"]
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

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # Source arn for API Gateway resource
  source_arn = "${module.apigateway_v2.apigatewayv2_api_execution_arn}/*/*"
}
