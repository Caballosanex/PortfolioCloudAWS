import json
import logging
import os
from datetime import datetime, timedelta, timezone
from urllib.request import Request, urlopen
from urllib.error import HTTPError

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SSM_PREFIX = "/cost-reporter/"


def lambda_handler(event, context):
    ssm = boto3.client("ssm", region_name=os.environ.get("AWS_REGION", "eu-west-1"))
    params = fetch_ssm_params(ssm)

    webhook_url = params.get("discord_webhook_url")
    ses_from = params.get("ses_from_email")
    ses_to = params.get("ses_to_email")

    if not webhook_url:
        logger.error("Missing required SSM parameter: discord_webhook_url")
        return {"statusCode": 500, "body": "Missing discord_webhook_url SSM parameter"}

    ce = boto3.client("ce", region_name="us-east-1")
    cost_data = gather_cost_data(ce)
    message = format_message(cost_data)

    logger.info("Formatted message length: %d chars", len(message))

    discord_ok = send_discord_webhook(webhook_url, message)

    ses_ok = False
    if ses_from and ses_to:
        ses_ok = send_ses_email(ses_from, ses_to, cost_data, message)

    return {
        "statusCode": 200,
        "body": json.dumps({
            "discord_sent": discord_ok,
            "ses_sent": ses_ok,
            "message_length": len(message),
        }),
    }


def fetch_ssm_params(ssm):
    param_names = [
        f"{SSM_PREFIX}discord_webhook_url",
        f"{SSM_PREFIX}ses_from_email",
        f"{SSM_PREFIX}ses_to_email",
    ]
    try:
        resp = ssm.get_parameters(Names=param_names, WithDecryption=True)
    except Exception:
        logger.exception("Failed to fetch SSM parameters")
        return {}

    return {
        p["Name"].replace(SSM_PREFIX, ""): p["Value"]
        for p in resp.get("Parameters", [])
    }


def gather_cost_data(ce):
    today = datetime.now(timezone.utc).date()
    month_start = today.replace(day=1)
    data = {}

    # MTD breakdown by record type (Usage, Credit, Tax)
    try:
        resp = ce.get_cost_and_usage(
            TimePeriod={"Start": month_start.isoformat(), "End": today.isoformat()},
            Granularity="MONTHLY",
            Metrics=["UnblendedCost"],
            GroupBy=[{"Type": "DIMENSION", "Key": "RECORD_TYPE"}],
        )
        record_types = {}
        for group in resp["ResultsByTime"][0].get("Groups", []):
            rtype = group["Keys"][0]
            amount = float(group["Metrics"]["UnblendedCost"]["Amount"])
            record_types[rtype] = amount

        data["gross_usage"] = record_types.get("Usage", 0.0)
        data["credits"] = record_types.get("Credit", 0.0)
        data["tax"] = record_types.get("Tax", 0.0)
        data["mtd_net"] = data["gross_usage"] + data["credits"] + data["tax"]
    except Exception:
        logger.exception("Failed to fetch MTD cost breakdown")
        data["gross_usage"] = None
        data["credits"] = None
        data["tax"] = None
        data["mtd_net"] = None

    # Top services by GROSS usage (before credits), last 7 days
    week_ago = today - timedelta(days=7)
    try:
        resp = ce.get_cost_and_usage(
            TimePeriod={"Start": week_ago.isoformat(), "End": today.isoformat()},
            Granularity="DAILY",
            Metrics=["UnblendedCost"],
            Filter={"Dimensions": {"Key": "RECORD_TYPE", "Values": ["Usage"]}},
            GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
        )
        service_totals = {}
        for day in resp["ResultsByTime"]:
            for group in day["Groups"]:
                svc = group["Keys"][0]
                cost = float(group["Metrics"]["UnblendedCost"]["Amount"])
                service_totals[svc] = service_totals.get(svc, 0.0) + cost

        top = sorted(service_totals.items(), key=lambda x: x[1], reverse=True)[:8]
        data["top_services"] = top
    except Exception:
        logger.exception("Failed to fetch top services")
        data["top_services"] = []

    # Month-end forecast
    try:
        month_end = (month_start.replace(month=month_start.month % 12 + 1, day=1)
                     if month_start.month < 12
                     else month_start.replace(year=month_start.year + 1, month=1, day=1))
        resp = ce.get_cost_forecast(
            TimePeriod={"Start": today.isoformat(), "End": month_end.isoformat()},
            Granularity="MONTHLY",
            Metric="UNBLENDED_COST",
        )
        data["forecast"] = float(resp["Total"]["Amount"])
    except Exception:
        logger.warning("Forecast unavailable (need >= 3 days of data)")
        data["forecast"] = None

    # Prior month gross usage + credits
    try:
        if month_start.month == 1:
            prev_start = month_start.replace(year=month_start.year - 1, month=12, day=1)
        else:
            prev_start = month_start.replace(month=month_start.month - 1)
        resp = ce.get_cost_and_usage(
            TimePeriod={"Start": prev_start.isoformat(), "End": month_start.isoformat()},
            Granularity="MONTHLY",
            Metrics=["UnblendedCost"],
            GroupBy=[{"Type": "DIMENSION", "Key": "RECORD_TYPE"}],
        )
        prev_types = {}
        for group in resp["ResultsByTime"][0].get("Groups", []):
            rtype = group["Keys"][0]
            prev_types[rtype] = float(group["Metrics"]["UnblendedCost"]["Amount"])
        data["prior_gross"] = prev_types.get("Usage", 0.0)
        data["prior_credits"] = prev_types.get("Credit", 0.0)
    except Exception:
        logger.exception("Failed to fetch prior month cost")
        data["prior_gross"] = None
        data["prior_credits"] = None

    # Total credits consumed since account creation (rolling 12 months max)
    try:
        twelve_months_ago = today.replace(year=today.year - 1)
        resp = ce.get_cost_and_usage(
            TimePeriod={"Start": twelve_months_ago.isoformat(), "End": today.isoformat()},
            Granularity="MONTHLY",
            Metrics=["UnblendedCost"],
            Filter={"Dimensions": {"Key": "RECORD_TYPE", "Values": ["Credit"]}},
        )
        total_credits = sum(
            float(m["Total"]["UnblendedCost"]["Amount"])
            for m in resp["ResultsByTime"]
        )
        data["total_credits_used"] = abs(total_credits)
    except Exception:
        logger.exception("Failed to fetch total credits")
        data["total_credits_used"] = None

    return data


def format_message(data):
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    next_monday = datetime.now(timezone.utc) + timedelta(days=7)
    next_date = next_monday.strftime("%Y-%m-%d")

    lines = [f"📊 **AWS Weekly Cost Report** — {today}", ""]

    gross = data.get("gross_usage")
    credits = data.get("credits")
    net = data.get("mtd_net")
    forecast = data.get("forecast")

    if gross is not None:
        lines.append(f"💰 Gross usage MTD: **${gross:.2f}**")
    if credits is not None and credits != 0:
        lines.append(f"🎁 Credits applied: **-${abs(credits):.2f}**")
    if net is not None:
        lines.append(f"💳 Net cost MTD: **${max(net, 0):.2f}**")
    if forecast is not None:
        lines.append(f"🔮 Forecast EOM (net): **${forecast:.2f}**")

    # Credits balance
    total_used = data.get("total_credits_used")
    if total_used is not None:
        remaining = max(200.0 - total_used, 0)
        lines.append(f"🏦 Credits remaining: **${remaining:.2f}** / $200.00 (${total_used:.2f} used)")

    # Prior month comparison (gross)
    prior_gross = data.get("prior_gross")
    if gross is not None and prior_gross is not None and prior_gross > 0:
        delta = gross - prior_gross
        pct = (delta / prior_gross) * 100
        sign = "+" if delta >= 0 else ""
        lines.append(f"📅 Gross vs last month: **{sign}${delta:.2f}** ({sign}{pct:.0f}%)")

    top = data.get("top_services", [])
    if top:
        lines.append("")
        lines.append("**Top services — last 7 days (gross):**")
        max_name = max(len(s[0]) for s in top)
        for svc, cost in top:
            if cost < 0.01:
                lines.append(f"`{svc:<{max_name}}`  ${cost:.4f}")
            else:
                lines.append(f"`{svc:<{max_name}}`  ${cost:.2f}")

    lines.append("")
    lines.append(f"_Next report: Mon {next_date} 08:00 UTC_")

    msg = "\n".join(lines)
    if len(msg) > 1990:
        msg = msg[:1990] + "\n..."
    return msg


def send_discord_webhook(webhook_url, message):
    data = json.dumps({"content": message}).encode()
    req = Request(
        webhook_url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "AWS-Cost-Reporter/1.0",
        },
        method="POST",
    )
    try:
        with urlopen(req, timeout=10) as resp:
            logger.info("Discord webhook sent, status %d", resp.status)
            return True
    except HTTPError as e:
        body = e.read().decode()
        logger.error("Discord webhook failed: %d %s — %s", e.code, e.reason, body)
        return False
    except Exception:
        logger.exception("Discord webhook failed")
        return False


def send_ses_email(from_email, to_email, cost_data, text_body):
    try:
        ses = boto3.client("ses", region_name=os.environ.get("AWS_REGION", "eu-west-1"))
        gross = cost_data.get("gross_usage")
        subject = f"AWS Weekly Cost Report — Gross ${gross:.2f}" if gross else "AWS Weekly Cost Report"
        ses.send_email(
            Source=from_email,
            Destination={"ToAddresses": [to_email]},
            Message={
                "Subject": {"Data": subject},
                "Body": {"Text": {"Data": text_body}},
            },
        )
        logger.info("SES email sent to %s", to_email)
        return True
    except Exception:
        logger.exception("Failed to send SES email")
        return False
