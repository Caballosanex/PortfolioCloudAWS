# --- ECS Cluster ---
resource "aws_ecs_cluster" "main" {
  name = var.project_name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = var.project_name
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }
}

# --- Security Groups ---
resource "aws_security_group" "fargate" {
  name        = "${var.project_name}-fargate-sg"
  description = "Allow inbound from VPC for Fargate tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SERP backend"
    from_port   = 5001
    to_port     = 5001
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    description = "CatLink + MatchCota backends"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-fargate-sg"
  }
}

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-efs-sg"
  description = "Allow NFS from Fargate tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "NFS from Fargate"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.fargate.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-efs-sg"
  }
}

# --- EFS for MatchCota Postgres ---
resource "aws_efs_file_system" "matchcota" {
  encrypted = true

  tags = {
    Name = "${var.project_name}-matchcota-pgdata"
  }
}

resource "aws_efs_mount_target" "matchcota_a" {
  file_system_id  = aws_efs_file_system.matchcota.id
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "matchcota_b" {
  file_system_id  = aws_efs_file_system.matchcota.id
  subnet_id       = aws_subnet.public_b.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "matchcota_pgdata" {
  file_system_id = aws_efs_file_system.matchcota.id

  posix_user {
    uid = 70
    gid = 70
  }

  root_directory {
    path = "/pgdata2"
    creation_info {
      owner_uid   = 70
      owner_gid   = 70
      permissions = "0700"
    }
  }

  tags = {
    Name = "${var.project_name}-matchcota-pgdata-ap"
  }
}

# --- IAM Roles ---

# Task execution role (ECR pull + CloudWatch logs)
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-ecs-execution-role" }
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role (EFS access)
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-ecs-task-role" }
}

resource "aws_iam_role_policy" "ecs_task_efs" {
  name = "${var.project_name}-ecs-task-efs"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess"
      ]
      Resource = aws_efs_file_system.matchcota.arn
    }]
  })
}

# --- CloudWatch Log Groups ---
resource "aws_cloudwatch_log_group" "serp" {
  name              = "/ecs/${var.project_name}/serp-backend"
  retention_in_days = 7
  tags              = { Name = "${var.project_name}-serp-logs" }
}

resource "aws_cloudwatch_log_group" "catlink" {
  name              = "/ecs/${var.project_name}/catlink-backend"
  retention_in_days = 7
  tags              = { Name = "${var.project_name}-catlink-logs" }
}

resource "aws_cloudwatch_log_group" "matchcota" {
  name              = "/ecs/${var.project_name}/matchcota-backend"
  retention_in_days = 7
  tags              = { Name = "${var.project_name}-matchcota-logs" }
}

resource "aws_cloudwatch_log_group" "matchcota_db" {
  name              = "/ecs/${var.project_name}/matchcota-db"
  retention_in_days = 7
  tags              = { Name = "${var.project_name}-matchcota-db-logs" }
}

# --- Cloud Map (Service Discovery) ---
resource "aws_service_discovery_private_dns_namespace" "main" {
  name = "portfolio.local"
  vpc  = aws_vpc.main.id
  tags = { Name = "${var.project_name}-namespace" }
}

resource "aws_service_discovery_service" "serp" {
  name          = "serp-backend"
  force_destroy = true

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "SRV"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "catlink" {
  name          = "catlink-backend"
  force_destroy = true

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "SRV"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "matchcota" {
  name          = "matchcota-backend"
  force_destroy = true

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "SRV"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# --- Task Definitions ---

# SERP Backend
resource "aws_ecs_task_definition" "serp" {
  family                   = "${var.project_name}-serp-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name      = "serp-backend"
    image     = "${aws_ecr_repository.backends["serp-backend"].repository_url}:latest"
    essential = true
    command   = ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "5001"]

    environment = [
      { name = "DEBUG", value = "0" }
    ]

    portMappings = [{
      containerPort = 5001
      protocol      = "tcp"
    }]

    healthCheck = {
      command     = ["CMD-SHELL", "python3 -c 'import urllib.request; urllib.request.urlopen(\"http://localhost:5001/health\")' || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.serp.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Name = "${var.project_name}-serp-backend" }
}

# CatLink Backend
resource "aws_ecs_task_definition" "catlink" {
  family                   = "${var.project_name}-catlink-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name      = "catlink-backend"
    image     = "${aws_ecr_repository.backends["catlink-backend"].repository_url}:latest"
    essential = true

    environment = [
      { name = "NOKIA_MOCK_MODE", value = "true" },
      { name = "BACKEND_HOST", value = "0.0.0.0" },
      { name = "BACKEND_PORT", value = "8000" }
    ]

    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]

    healthCheck = {
      command     = ["CMD-SHELL", "python3 -c 'import urllib.request; urllib.request.urlopen(\"http://localhost:8000/api/chargers\")' || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.catlink.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Name = "${var.project_name}-catlink-backend" }
}

# MatchCota (backend + postgres sidecar)
resource "aws_ecs_task_definition" "matchcota" {
  family                   = "${var.project_name}-matchcota"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  volume {
    name = "matchcota-pgdata"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.matchcota.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.matchcota_pgdata.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "matchcota-db"
      image     = "${aws_ecr_repository.backends["matchcota-db"].repository_url}:latest"
      essential = true

      environment = [
        { name = "POSTGRES_USER", value = "matchcota" },
        { name = "POSTGRES_PASSWORD", value = "matchcota_demo_pass" },
        { name = "POSTGRES_DB", value = "matchcota" },
        { name = "PGDATA", value = "/var/lib/postgresql/data/pgdata" }
      ]

      portMappings = [{
        containerPort = 5432
        protocol      = "tcp"
      }]

      mountPoints = [{
        sourceVolume  = "matchcota-pgdata"
        containerPath = "/var/lib/postgresql/data"
        readOnly      = false
      }]

      healthCheck = {
        command     = ["CMD-SHELL", "pg_isready -U matchcota"]
        interval    = 10
        timeout     = 5
        retries     = 5
        startPeriod = 30
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.matchcota_db.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },
    {
      name      = "matchcota-backend"
      image     = "${aws_ecr_repository.backends["matchcota-backend"].repository_url}:latest"
      essential = true

      dependsOn = [{
        containerName = "matchcota-db"
        condition     = "HEALTHY"
      }]

      environment = [
        { name = "ENVIRONMENT", value = "development" },
        { name = "DEBUG", value = "false" },
        { name = "DATABASE_URL", value = "postgresql://matchcota:matchcota_demo_pass@localhost:5432/matchcota" },
        { name = "REDIS_ENABLED", value = "false" },
        { name = "S3_ENABLED", value = "false" },
        { name = "SECRET_KEY", value = "demo-portfolio-secret-key-not-for-production" },
        { name = "JWT_SECRET_KEY", value = "demo-portfolio-jwt-secret-key-not-for-production" },
        { name = "WILDCARD_DOMAIN", value = "matchcota.local" }
      ]

      portMappings = [{
        containerPort = 8000
        protocol      = "tcp"
      }]

      healthCheck = {
        command     = ["CMD-SHELL", "python3 -c 'import urllib.request; urllib.request.urlopen(\"http://localhost:8000/api/v1/health\")' || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 120
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.matchcota.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = { Name = "${var.project_name}-matchcota" }
}

# --- ECS Services ---
resource "aws_ecs_service" "serp" {
  name            = "serp-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.serp.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = [aws_subnet.public.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.fargate.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.serp.arn
    container_name = "serp-backend"
    container_port = 5001
  }

  tags = { Name = "${var.project_name}-serp-service" }
}

resource "aws_ecs_service" "catlink" {
  name            = "catlink-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.catlink.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = [aws_subnet.public.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.fargate.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.catlink.arn
    container_name = "catlink-backend"
    container_port = 8000
  }

  tags = { Name = "${var.project_name}-catlink-service" }
}

resource "aws_ecs_service" "matchcota" {
  name            = "matchcota"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.matchcota.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = [aws_subnet.public.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.fargate.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.matchcota.arn
    container_name = "matchcota-backend"
    container_port = 8000
  }

  tags = { Name = "${var.project_name}-matchcota-service" }
}
