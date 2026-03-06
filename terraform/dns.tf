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
