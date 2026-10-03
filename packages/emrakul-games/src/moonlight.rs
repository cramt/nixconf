//! What Moonlight.conf says about this client and the hosts it is paired
//! with. Keys are moonlight-qt 6.1's (backend/identitymanager.cpp,
//! backend/nvcomputer.cpp, backend/computermanager.cpp), the same ones
//! moonlight-seed writes.

use std::{collections::BTreeSet, fmt, path::PathBuf};

use anyhow::{Context, bail};
use rustls_pki_types::{CertificateDer, PrivateKeyDer, pem::PemObject};
use serde::{Deserialize, Serialize};

use crate::qsettings::Settings;

/// GameStream's HTTP port, and Sunshine's default.
const DEFAULT_HTTP_PORT: u16 = 47989;

pub struct Conf {
    pub identity: Identity,
    pub hosts: Vec<PairedHost>,
}

/// The client cert every paired host pinned, and its key.
pub struct Identity {
    pub cert: CertificateDer<'static>,
    pub key: PrivateKeyDer<'static>,
    pub unique_id: String,
}

/// A host Moonlight holds the server cert of. Hosts it only found on the
/// network have none and aren't one.
pub struct PairedHost {
    pub uuid: HostUuid,
    /// What Moonlight shows for it: Sunshine's name, or what it was renamed
    /// to in Moonlight.
    pub name: String,
    pub addresses: Addresses,
    pub server_cert: CertificateDer<'static>,
    /// Apps hidden in Moonlight's app grid.
    pub hidden: BTreeSet<String>,
}

/// Sunshine's uniqueid, lowercased. Only hex digits and dashes, so it can
/// name files.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct HostUuid(String);

impl TryFrom<String> for HostUuid {
    type Error = anyhow::Error;

    fn try_from(raw: String) -> anyhow::Result<Self> {
        if raw.is_empty() || !raw.chars().all(|c| c.is_ascii_hexdigit() || c == '-') {
            bail!("not a host uuid: {raw:?}");
        }
        Ok(Self(raw.to_ascii_lowercase()))
    }
}

impl From<HostUuid> for String {
    fn from(uuid: HostUuid) -> Self {
        uuid.0
    }
}

impl fmt::Display for HostUuid {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Address {
    pub host: String,
    pub http_port: u16,
}

impl Address {
    /// Sunshine listens for HTTPS 5 below its HTTP port.
    pub fn https_port(&self) -> u16 {
        self.http_port.saturating_sub(5)
    }

    /// The host part of a URL or socket address: IPv6 in brackets.
    pub fn host_for_url(&self) -> String {
        if self.host.contains(':') {
            format!("[{}]", self.host)
        } else {
            self.host.clone()
        }
    }
}

/// How `moonlight stream` takes it: the port only when it isn't the default.
impl fmt::Display for Address {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.http_port == DEFAULT_HTTP_PORT {
            f.write_str(&self.host)
        } else {
            write!(f, "{}:{}", self.host_for_url(), self.http_port)
        }
    }
}

/// Where a host may be, best first. Never empty.
pub struct Addresses {
    pub preferred: Address,
    pub others: Vec<Address>,
}

impl Addresses {
    fn new(mut all: Vec<Address>) -> Option<Self> {
        let mut seen = Vec::new();
        all.retain(|a| {
            let new = !seen.contains(a);
            seen.push(a.clone());
            new
        });
        let mut all = all.into_iter();
        Some(Self {
            preferred: all.next()?,
            others: all.collect(),
        })
    }

    pub fn iter(&self) -> impl Iterator<Item = &Address> {
        std::iter::once(&self.preferred).chain(&self.others)
    }
}

/// `~/.config/Moonlight Game Streaming Project/Moonlight.conf`.
pub fn default_path() -> anyhow::Result<PathBuf> {
    let config = crate::env_dir("XDG_CONFIG_HOME")
        .or_else(|| Some(crate::env_dir("HOME")?.join(".config")))
        .context("neither XDG_CONFIG_HOME nor HOME is set")?;
    Ok(config.join("Moonlight Game Streaming Project/Moonlight.conf"))
}

impl Conf {
    pub fn parse(text: &str) -> anyhow::Result<Self> {
        let settings = Settings::parse(text);
        let identity = Identity {
            cert: settings
                .bytes("certificate")
                .context("no client certificate: Moonlight hasn't run yet")
                .and_then(|pem| {
                    CertificateDer::from_pem_slice(pem).context("the client certificate")
                })?,
            key: settings
                .bytes("key")
                .context("no client key")
                .and_then(|pem| PrivateKeyDer::from_pem_slice(pem).context("the client key"))?,
            unique_id: settings
                .text("uniqueid")
                .context("no client uniqueid")?
                .to_owned(),
        };
        // A non-empty hostsbackup means Moonlight died mid-flush, and it reads
        // that instead of hosts on its next start (ComputerManager's
        // constructor). Read whichever it will.
        let array = if settings.array_len("hostsbackup") > 0 {
            "hostsbackup"
        } else {
            "hosts"
        };
        let hosts = (1..=settings.array_len(array))
            .filter_map(|i| paired_host(&settings, &format!("{array}/{i}")))
            .collect();
        Ok(Self { identity, hosts })
    }
}

fn paired_host(settings: &Settings, prefix: &str) -> Option<PairedHost> {
    let key = |name: &str| format!("{prefix}/{name}");
    let server_cert = CertificateDer::from_pem_slice(settings.bytes(&key("srvcert"))?).ok()?;
    let uuid = HostUuid::try_from(settings.text(&key("uuid"))?.to_owned()).ok()?;
    // NvComputer's own order of preference: what was typed in, what it
    // found on the LAN, then the rest.
    let addresses = ["manual", "local", "remote", "ipv6"]
        .into_iter()
        .filter_map(|kind| {
            let host = settings.text(&key(&format!("{kind}address")))?;
            let port = settings
                .text(&key(&format!("{kind}port")))
                .and_then(|p| p.parse().ok())
                .filter(|&p| p != 0)
                .unwrap_or(DEFAULT_HTTP_PORT);
            (!host.is_empty()).then(|| Address {
                host: host.to_owned(),
                http_port: port,
            })
        })
        .collect();
    let addresses = Addresses::new(addresses)?;
    let name = settings
        .text(&key("hostname"))
        .filter(|n| !n.is_empty())
        .map_or_else(|| uuid.to_string(), str::to_owned);
    let apps = key("apps");
    let hidden = (1..=settings.array_len(&apps))
        .filter(|j| settings.text(&format!("{apps}/{j}/hidden")) == Some("true"))
        .filter_map(|j| {
            settings
                .text(&format!("{apps}/{j}/name"))
                .map(str::to_owned)
        })
        .collect();
    Some(PairedHost {
        uuid,
        name,
        addresses,
        server_cert,
        hidden,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    // A throwaway self-signed cert and its key, paired with nothing.
    const CERT: &str = "-----BEGIN CERTIFICATE-----\\nMIIBjjCCATWgAwIBAgIUGOdEFadvAjeCoDf4F3riXdLHbAcwCgYIKoZIzj0EAwIw\\nHTEbMBkGA1UEAwwSZW1yYWt1bC1nYW1lcy10ZXN0MB4XDTI2MTAwMzEzMTAzMloX\\nDTM2MDkzMDEzMTAzMlowHTEbMBkGA1UEAwwSZW1yYWt1bC1nYW1lcy10ZXN0MFkw\\nEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAESWHiX+AbqewHhJNVFzoULVH2sZf6/DIx\\nd36S5kD4xr8QSVkZDKVlN+83vbAxrSbBsJG0QvBHuuIwrUMHgHBhGqNTMFEwHQYD\\nVR0OBBYEFBzp5NocoSbRRQNos9r/X5zfZf7PMB8GA1UdIwQYMBaAFBzp5NocoSbR\\nRQNos9r/X5zfZf7PMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDRwAwRAIg\\nGqIURi+q5CmTBjuHFHm8kXNDtSLivkFwU8Ug+voS4EICIARUhvxE2w4YU1IwHSU5\\nO2VCLQzg60KYFxShN80hBbjW\\n-----END CERTIFICATE-----\\n";
    const KEY: &str = "-----BEGIN PRIVATE KEY-----\\nMIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgfaKbkJFg19F/ssRI\\nEaFfdltnAVe/ixgdtJ6cD92l1v6hRANCAARJYeJf4Bup7AeEk1UXOhQtUfaxl/r8\\nMjF3fpLmQPjGvxBJWRkMpWU37ze9sDGtJsGwkbRC8Ee64jCtQweAcGEa\\n-----END PRIVATE KEY-----\\n";

    fn conf(hosts: &str) -> String {
        format!(
            "[General]\ncertificate=@ByteArray({CERT})\nkey=\"@ByteArray({KEY})\"\nuniqueid=0123456789abcdef\n\n[hosts]\n{hosts}"
        )
    }

    #[test]
    fn paired_hosts_with_their_addresses_and_hidden_apps() {
        let conf = Conf::parse(&conf(&format!(
            concat!(
                "1\\apps\\1\\hidden=false\n1\\apps\\1\\name=Desktop\n",
                "1\\apps\\2\\hidden=true\n1\\apps\\2\\name=Steam Big Picture\n",
                "1\\apps\\size=2\n",
                "1\\hostname=saturn\n1\\localaddress=192.168.178.23\n1\\localport=47989\n",
                "1\\manualaddress=192.168.178.23\n1\\manualport=47989\n",
                "1\\remoteaddress=\n1\\ipv6address=fe80::1\n1\\ipv6port=48000\n",
                "1\\srvcert=@ByteArray({cert})\n1\\uuid=3F551B46-50D0-4758-B9B9-AA492AE1178B\n",
                "2\\hostname=found-on-lan\n2\\localaddress=192.168.178.99\n",
                "2\\srvcert=@ByteArray()\n2\\uuid=AAAA\n",
                "size=2\n",
            ),
            cert = CERT
        )))
        .unwrap();
        assert_eq!(conf.identity.unique_id, "0123456789abcdef");
        let [saturn] = &conf.hosts[..] else {
            panic!("only the paired host")
        };
        assert_eq!(
            saturn.uuid.to_string(),
            "3f551b46-50d0-4758-b9b9-aa492ae1178b"
        );
        assert_eq!(saturn.name, "saturn");
        let addresses: Vec<String> = saturn.addresses.iter().map(Address::to_string).collect();
        assert_eq!(addresses, ["192.168.178.23", "[fe80::1]:48000"]);
        assert_eq!(saturn.addresses.preferred.https_port(), 47984);
        assert_eq!(
            saturn.hidden.iter().collect::<Vec<_>>(),
            ["Steam Big Picture"]
        );
    }

    #[test]
    fn without_an_identity_there_is_nothing_to_do() {
        assert!(Conf::parse("[General]\nuniqueid=x\n").is_err());
    }

    #[test]
    fn host_uuids_can_name_files() {
        assert!(HostUuid::try_from("../etc".to_owned()).is_err());
        assert!(HostUuid::try_from(String::new()).is_err());
    }
}
