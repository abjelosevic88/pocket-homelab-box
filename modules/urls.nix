# URLs of the box, from pocket.box.{domain,httpsPort,httpPort}.
cfg:
let
  httpsSuffix = if cfg.httpsPort == 443 then "" else ":${toString cfg.httpsPort}";
  httpSuffix = if cfg.httpPort == 80 then "" else ":${toString cfg.httpPort}";
in
{
  # https://<name>.<domain> for an app or service.
  site = name: "https://${name}.${cfg.domain}${httpsSuffix}";
  host = name: "${name}.${cfg.domain}";
  # Plain-http landing page with the certificate download.
  landing = "http://${cfg.domain}${httpSuffix}";
  caDir = "/var/lib/pocket-box-ca";
  caCert = "/var/lib/pocket-box-ca/pocket-box-ca.crt";
  caBundle = "/var/lib/pocket-box-ca/ca-bundle.crt";
}
