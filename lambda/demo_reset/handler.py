import boto3
import os

ecs = boto3.client("ecs")

CLUSTER = os.environ["ECS_CLUSTER"]
SERVICES = os.environ["ECS_SERVICES"].split(",")


def lambda_handler(event, context):
    results = {}
    for service in SERVICES:
        service = service.strip()
        ecs.update_service(
            cluster=CLUSTER,
            service=service,
            forceNewDeployment=True,
        )
        results[service] = "restarted"

    return {"statusCode": 200, "body": results}
