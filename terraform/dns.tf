# Cloudflare DNS records pointing to the Elastic IP
resource "cloudflare_record" "root" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  content = aws_eip.web.public_ip
  type    = "A"
  ttl     = 300
  proxied = false # Direct connection, SSL handled by Certbot
}

resource "cloudflare_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  content = aws_eip.web.public_ip
  type    = "A"
  ttl     = 300
  proxied = false
}

# CAA records — restrict certificate issuance to Let's Encrypt only
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
