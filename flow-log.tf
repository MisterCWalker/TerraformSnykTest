resource "aws_cloudwatch_log_group" "vpc_flow_log_group" {
  name              = "vpc-flow-log-group"
  retention_in_days = 7
}

resource "aws_flow_log" "vpc_flow_log" {
  log_destination      = aws_cloudwatch_log_group.vpc_flow_log_group.arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id
  iam_role_arn         = aws_iam_role.flow_log_role.arn
}
