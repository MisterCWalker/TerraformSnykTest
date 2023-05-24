resource "aws_apigatewayv2_api" "myhttpapi" {
  name          = "my-http-api"
  protocol_type = "HTTP"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.myhttpapi.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "my_lambda" {
  api_id           = aws_apigatewayv2_api.myhttpapi.id
  integration_type = "AWS_PROXY"

  integration_uri = aws_lambda_function.my_lambda.invoke_arn
}

resource "aws_apigatewayv2_route" "example" {
  api_id    = aws_apigatewayv2_api.myhttpapi.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.my_lambda.id}"
}

resource "aws_apigatewayv2_deployment" "example" {
  api_id      = aws_apigatewayv2_api.myhttpapi.id
  description = "My deployment"

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_apigatewayv2_route.example
  ]
}

resource "aws_apigatewayv2_stage" "example" {
  api_id        = aws_apigatewayv2_api.myhttpapi.id
  name          = "example-stage"
  deployment_id = aws_apigatewayv2_deployment.example.id
  auto_deploy   = true
}
