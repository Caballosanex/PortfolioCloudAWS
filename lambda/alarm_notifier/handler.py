"""Forward CloudWatch alarm state changes (delivered via SNS) to a Discord webhook."""

import json
import logging
import os
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

WEBHOOK_PARAM = "/cost-reporter/discord_webhook_url"

COLORS = {"ALARM": 0xE74C3C, "OK": 0x2ECC71, "INSUFFICIENT_DATA": 0x95A5A6}
ICONS = {"ALARM": "\U0001F6A8", "OK": "✅", "INSUFFICIENT_DATA": "❓"}

_webhook_url = None


def get_webhook_url():
    global _webhook_url
    if _webhook_url is None:
        ssm = boto3.client("ssm", region_name=os.environ.get("AWS_REGION", "eu-west-1"))
        _webhook_url = ssm.get_parameter(Name=WEBHOOK_PARAM, WithDecryption=True)["Parameter"]["Value"]
    return _webhook_url


def build_payload(alarm):
    state = alarm.get("NewStateValue", "UNKNOWN")
    name = alarm.get("AlarmName", "unknown alarm")
    description = alarm.get("AlarmDescription") or ""
    reason = alarm.get("NewStateReason", "")
    region = alarm.get("Region", "")
    fields = [{"name": "Reason", "value": reason[:1000] or "n/a"}]
    if description:
        fields.insert(0, {"name": "What it means", "value": description[:500]})
    return {
        "embeds": [
            {
                "title": f"{ICONS.get(state, '')} {state}: {name}",
                "color": COLORS.get(state, 0x95A5A6),
                "fields": fields,
                "footer": {"text": f"CloudWatch | {region}"},
                "timestamp": alarm.get("StateChangeTime"),
            }
        ]
    }


def post(webhook_url, payload):
    req = Request(
        webhook_url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "AWS-Alarm-Notifier/1.0"},
        method="POST",
    )
    try:
        with urlopen(req, timeout=10) as resp:
            logger.info("Discord webhook sent, status %d", resp.status)
    except HTTPError as e:
        logger.error("Discord webhook failed: %d %s %s", e.code, e.reason, e.read().decode())
        raise


def lambda_handler(event, context):
    webhook_url = get_webhook_url()
    for record in event.get("Records", []):
        message = record["Sns"]["Message"]
        try:
            alarm = json.loads(message)
            if not isinstance(alarm, dict) or "AlarmName" not in alarm:
                raise ValueError("not a CloudWatch alarm")
        except ValueError:
            # Not a CloudWatch alarm (e.g. AWS Budgets): forward as plain text.
            subject = record["Sns"].get("Subject") or "AWS notification"
            post(webhook_url, {"content": f"**{subject}**\n{message}"[:1900]})
            continue
        logger.info("Alarm %s -> %s", alarm.get("AlarmName"), alarm.get("NewStateValue"))
        post(webhook_url, build_payload(alarm))
    return {"statusCode": 200}
