# DynamoDB table for CV visit counter
resource "aws_dynamodb_table" "cv_counter" {
  name         = "cv-visit-counter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "${var.project_name}-cv-counter"
  }
}
