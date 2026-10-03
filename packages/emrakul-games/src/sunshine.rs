//! Asking a paired Sunshine what it streams, over GameStream's HTTPS API:
//! the client cert Moonlight paired with, and the host's cert pinned
//! exactly as Moonlight pins it.

use std::{
    io::{Read, Write},
    net::{TcpStream, ToSocketAddrs},
    sync::Arc,
    time::Duration,
};

use anyhow::{Context, anyhow, bail};
use rustls::{
    ClientConfig, ClientConnection, DigitallySignedStruct, SignatureScheme, StreamOwned,
    client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
    crypto::WebPkiSupportedAlgorithms,
};
use rustls_pki_types::{CertificateDer, ServerName, UnixTime};
use serde::{Deserialize, Serialize};

use crate::moonlight::{Address, Identity, PairedHost};

/// A sleeping or switched-off host should cost a couple of seconds, not a
/// TCP timeout's minutes.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(2);
const IO_TIMEOUT: Duration = Duration::from_secs(10);
/// Box art is a few hundred KB; anything far past that isn't box art.
const MAX_BODY: usize = 16 << 20;

/// Sunshine's id for an app. Numeric, so it can name files.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub struct AppId(pub i64);

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct App {
    pub id: AppId,
    pub name: String,
}

pub struct Client {
    config: Arc<ClientConfig>,
    unique_id: String,
}

impl Client {
    pub fn new(identity: &Identity, host: &PairedHost) -> anyhow::Result<Self> {
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let verifier = Pinned {
            cert: host.server_cert.clone(),
            algorithms: provider.signature_verification_algorithms,
        };
        let mut config = ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()?
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(verifier))
            .with_client_auth_cert(vec![identity.cert.clone()], identity.key.clone_key())
            .context("the client identity")?;
        // Sunshine fails a resumed session with an internal_error alert: it
        // verifies client certs (verify_peer | verify_client_once) but never
        // sets a session id context, and OpenSSL refuses to resume without
        // one. Every connection is a full handshake until Sunshine sets it.
        // https://github.com/LizardByte/Sunshine/blob/82a9720e/src/nvhttp.cpp
        config.resumption = rustls::client::Resumption::disabled();
        Ok(Self {
            config: Arc::new(config),
            unique_id: identity.unique_id.clone(),
        })
    }

    /// `/applist`: every app the host would stream to us.
    pub fn apps(&self, address: &Address) -> anyhow::Result<Vec<App>> {
        let body = self.get(address, "applist", "")?;
        parse_applist(std::str::from_utf8(&body).context("applist isn't UTF-8")?)
    }

    /// `/appasset`: an app's box art, a PNG.
    pub fn box_art(&self, address: &Address, app: AppId) -> anyhow::Result<Vec<u8>> {
        self.get(
            address,
            "appasset",
            &format!("&appid={}&AssetType=2&AssetIdx=0", app.0),
        )
    }

    fn get(&self, address: &Address, endpoint: &str, query: &str) -> anyhow::Result<Vec<u8>> {
        let target = (address.host.as_str(), address.https_port())
            .to_socket_addrs()
            .with_context(|| format!("resolving {}", address.host))?
            .next()
            .with_context(|| format!("{} resolves to nothing", address.host))?;
        let socket = TcpStream::connect_timeout(&target, CONNECT_TIMEOUT)
            .with_context(|| format!("connecting to {target}"))?;
        socket.set_read_timeout(Some(IO_TIMEOUT))?;
        socket.set_write_timeout(Some(IO_TIMEOUT))?;
        let name = ServerName::try_from(address.host.clone())
            .with_context(|| format!("{} as a TLS server name", address.host))?;
        let connection = ClientConnection::new(self.config.clone(), name)?;
        let mut tls = StreamOwned::new(connection, socket);
        write!(
            tls,
            "GET /{endpoint}?uniqueid={}{query} HTTP/1.1\r\nHost: {}:{}\r\nConnection: close\r\n\r\n",
            self.unique_id,
            address.host_for_url(),
            address.https_port(),
        )?;
        tls.flush()?;
        read_response(&mut tls).with_context(|| format!("GET /{endpoint} from {target}"))
    }
}

/// Reads one HTTP/1.1 response, done as soon as Content-Length is in:
/// Sunshine needn't close the connection, or send close_notify when it does.
fn read_response(stream: &mut impl Read) -> anyhow::Result<Vec<u8>> {
    let mut buf = Vec::new();
    let mut chunk = [0u8; 16 << 10];
    loop {
        if let Some(head_end) = find(&buf, b"\r\n\r\n") {
            let head = std::str::from_utf8(&buf[..head_end]).context("response head")?;
            let mut lines = head.split("\r\n");
            let status = lines
                .next()
                .and_then(|l| l.split(' ').nth(1))
                .context("no status line")?;
            if status != "200" {
                bail!("HTTP {status}");
            }
            let header = |name: &str| {
                lines.clone().find_map(|l| {
                    let (k, v) = l.split_once(':')?;
                    k.trim().eq_ignore_ascii_case(name).then(|| v.trim())
                })
            };
            if header("transfer-encoding").is_some_and(|v| !v.eq_ignore_ascii_case("identity")) {
                bail!("chunked responses aren't supported");
            }
            let length: Option<usize> = header("content-length").map(str::parse).transpose()?;
            let body_start = head_end + 4;
            if let Some(length) = length {
                if length > MAX_BODY {
                    bail!("a {length} byte body");
                }
                if buf.len() >= body_start + length {
                    return Ok(buf[body_start..body_start + length].to_vec());
                }
            }
            match stream.read(&mut chunk) {
                Ok(0) | Err(_) if length.is_none() => return Ok(buf.split_off(body_start)),
                Ok(0) => bail!("connection closed mid-body"),
                Ok(n) => buf.extend_from_slice(&chunk[..n]),
                Err(err) => return Err(err.into()),
            }
        } else {
            match stream.read(&mut chunk)? {
                0 => bail!("connection closed before a response"),
                n => buf.extend_from_slice(&chunk[..n]),
            }
        }
        if buf.len() > MAX_BODY {
            bail!("response too large");
        }
    }
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

/// `<root status_code="200"><App><AppTitle>..</AppTitle><ID>..</ID></App>..</root>`
fn parse_applist(xml: &str) -> anyhow::Result<Vec<App>> {
    let doc = roxmltree::Document::parse(xml).context("applist isn't XML")?;
    let root = doc.root_element();
    match root.attribute("status_code") {
        Some("200") => {}
        status => bail!(
            "applist status {}: {}",
            status.unwrap_or("missing"),
            root.attribute("status_message").unwrap_or("")
        ),
    }
    root.children()
        .filter(|n| n.has_tag_name("App"))
        .map(|app| {
            let name = child(app, "AppTitle").context("an app without a title")?;
            let id = child(app, "ID")
                .and_then(|id| id.trim().parse().ok())
                .ok_or_else(|| anyhow!("{name} has no numeric ID"))?;
            Ok(App {
                id: AppId(id),
                name: name.to_owned(),
            })
        })
        .collect()
}

fn child<'a>(app: roxmltree::Node<'a, '_>, tag: &str) -> Option<&'a str> {
    app.children()
        .find(|n| n.has_tag_name(tag))
        .and_then(|n| n.text())
}

/// Trusts exactly the cert the host paired with, the way Moonlight does:
/// Sunshine's cert is self-signed and names no host.
#[derive(Debug)]
struct Pinned {
    cert: CertificateDer<'static>,
    algorithms: WebPkiSupportedAlgorithms,
}

impl ServerCertVerifier for Pinned {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        if end_entity.as_ref() == self.cert.as_ref() {
            Ok(ServerCertVerified::assertion())
        } else {
            Err(rustls::Error::InvalidCertificate(
                rustls::CertificateError::ApplicationVerificationFailure,
            ))
        }
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(message, cert, dss, &self.algorithms)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(message, cert, dss, &self.algorithms)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algorithms.supported_schemes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn applist() {
        let apps = parse_applist(r#"<?xml version="1.0" encoding="utf-8"?>
<root status_code="200"><App><IsHdrSupported>1</IsHdrSupported><AppTitle>Desktop</AppTitle><ID>881448767</ID></App><App><IsHdrSupported>1</IsHdrSupported><AppTitle>V Rising &amp; co</AppTitle><ID>2117436889</ID></App></root>"#).unwrap();
        assert_eq!(
            apps,
            [
                App {
                    id: AppId(881448767),
                    name: "Desktop".into()
                },
                App {
                    id: AppId(2117436889),
                    name: "V Rising & co".into()
                },
            ]
        );
        assert!(
            parse_applist(
                r#"<root status_code="401" status_message="The client is not authorized"/>"#
            )
            .is_err()
        );
        assert_eq!(parse_applist(r#"<root status_code="200"/>"#).unwrap(), []);
    }

    #[test]
    fn responses() {
        let read = |raw: &[u8]| read_response(&mut &raw[..]);
        assert_eq!(
            read(b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabcdef").unwrap(),
            b"abc"
        );
        assert_eq!(
            read(b"HTTP/1.1 200 OK\r\n\r\nto the end").unwrap(),
            b"to the end"
        );
        assert!(read(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n").is_err());
        assert!(read(b"HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nshort").is_err());
    }
}
