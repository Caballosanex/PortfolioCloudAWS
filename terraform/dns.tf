# Cloudflare DNS records → CloudFront
resource "cloudflare_record" "root" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CNAME"
  content = aws_cloudfront_distribution.main.domain_name
  ttl     = 300
  proxied = false
}

resource "cloudflare_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  type    = "CNAME"
  content = aws_cloudfront_distribution.main.domain_name
  ttl     = 300
  proxied = false
}

# CAA records — allow both Let's Encrypt (EC2) and Amazon (CloudFront/ACM)
resource "cloudflare_record" "caa_issue" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CAA"
  ttl     = 300
  data {
    flags = "0"
    tag   = "issue"
    value = "letsencrypt.org"
  }
}

resource "cloudflare_record" "caa_issue_amazon" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CAA"
  ttl     = 300
  data {
    flags = "0"
    tag   = "issue"
    value = "amazon.com"
  }
}

resource "cloudflare_record" "caa_issuewild" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CAA"
  ttl     = 300
  data {
    flags = "0"
    tag   = "issuewild"
    value = "letsencrypt.org"
  }
}

resource "cloudflare_record" "caa_issuewild_amazon" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CAA"
  ttl     = 300
  data {
    flags = "0"
    tag   = "issuewild"
    value = "amazon.com"
  }
}

resource "cloudflare_record" "caa_iodef" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CAA"
  ttl     = 300
  data {
    flags = "0"
    tag   = "iodef"
    value = "mailto:alexsanchezblabia@gmail.com"
  }
}

# ACM DNS validation record
resource "cloudflare_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront.domain_validation_options :
    dvo.resource_record_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }...
  }

  zone_id         = var.cloudflare_zone_id
  name            = each.value[0].name
  type            = each.value[0].type
  content         = each.value[0].record
  ttl             = 300
  proxied         = false
  allow_overwrite = true
}

# SPF — domain sends no mail, reject all
resource "cloudflare_record" "spf" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  ttl     = 300
  content = "v=spf1 -all"
}

# DMARC — reject spoofed mail, send reports to inbox
resource "cloudflare_record" "dmarc" {
  zone_id = var.cloudflare_zone_id
  name    = "_dmarc"
  type    = "TXT"
  ttl     = 300
  content = "v=DMARC1; p=reject; sp=reject; rua=mailto:alexsanchezblabia@gmail.com"
}
