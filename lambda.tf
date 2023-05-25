resource "aws_lambda_function" "my_lambda" {
  function_name = "my_lambda"
  handler       = "index.handler"
  role          = aws_iam_role.iam_for_lambda.arn
  runtime       = "nodejs14.x"

  filename = "lambda/function.zip"
}
