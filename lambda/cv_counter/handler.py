import json
import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("cv-visit-counter")


def lambda_handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path = event.get("rawPath", "")

    headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    }

    if method == "OPTIONS":
        return {"statusCode": 200, "headers": headers, "body": ""}

    if method == "POST" and "/count" in path:
        resp = table.update_item(
            Key={"id": "global"},
            UpdateExpression="SET #c = if_not_exists(#c, :zero) + :inc",
            ExpressionAttributeNames={"#c": "count"},
            ExpressionAttributeValues={":inc": 1, ":zero": 0},
            ReturnValues="UPDATED_NEW",
        )
        count = int(resp["Attributes"]["count"])
        return {
            "statusCode": 200,
            "headers": headers,
            "body": json.dumps({"count": count}),
        }

    if method == "GET" and "/count" in path:
        resp = table.get_item(Key={"id": "global"})
        count = int(resp.get("Item", {}).get("count", 0))
        return {
            "statusCode": 200,
            "headers": headers,
            "body": json.dumps({"count": count}),
        }

    return {
        "statusCode": 404,
        "headers": headers,
        "body": json.dumps({"error": "not found"}),
    }
