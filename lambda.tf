data "archive_file" "python_lambda_package" {
  type        = "zip"
  source_file = "code/lambda_function.py"
  output_path = "hello_world.zip"
}

resource "aws_lambda_function" "my_lambda" {
  function_name    = "my_lambda"
  filename         = "hello_world.zip"
  source_code_hash = data.archive_file.python_lambda_package.output_base64sha256
  role             = aws_iam_role.iam_for_lambda.arn
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  timeout          = 10

}

resource "aws_lambda_function" "authorization" {
  function_name = "ApiGatewayTokenAuthorizerEvent"
  runtime       = "nodejs14.x"
  handler       = "index.handler"
  timeout       = 10
  memory_size   = 128
  filename      = "code/lambda_function.js"
  role          = aws_iam_role.iam_for_lambda.arn
}
