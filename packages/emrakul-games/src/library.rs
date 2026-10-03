//! Which games Home gets: every app of every paired host, as last listed.
//! A host that doesn't answer (asleep, switched off) keeps its games, so
//! their tiles stay and Moonlight can wake it; only a host that answers can
//! take a game away.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::{
    moonlight::{Address, HostUuid, PairedHost},
    sunshine::App,
};

/// What the hosts last listed, kept across runs and sessions.
#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Library {
    hosts: BTreeMap<HostUuid, Listing>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Listing {
    /// Where it answered from: where to stream it from.
    pub address: Address,
    pub apps: Vec<App>,
}

/// What asking a host got.
pub enum Answer {
    Listed(Listing),
    /// Unreachable, or it answered with something other than its app list.
    Silent,
}

impl Library {
    /// The hosts still paired, each with what it just listed or, if it
    /// didn't answer, what it listed last.
    pub fn update(mut self, answers: impl IntoIterator<Item = (HostUuid, Answer)>) -> Self {
        let hosts = answers
            .into_iter()
            .filter_map(|(uuid, answer)| {
                let listing = match answer {
                    Answer::Listed(listing) => listing,
                    Answer::Silent => self.hosts.remove(&uuid)?,
                };
                Some((uuid, listing))
            })
            .collect();
        Self { hosts }
    }

    pub fn listing(&self, uuid: &HostUuid) -> Option<&Listing> {
        self.hosts.get(uuid)
    }

    /// One game per app not hidden in Moonlight, named after the app. An app
    /// name more than one host has gets the host's name after it.
    pub fn games(&self, hosts: &[PairedHost]) -> Vec<Game> {
        let shown: Vec<(&PairedHost, &Listing, &App)> = hosts
            .iter()
            .filter_map(|host| Some((host, self.hosts.get(&host.uuid)?)))
            .flat_map(|(host, listing)| {
                listing
                    .apps
                    .iter()
                    .filter(|app| !host.hidden.contains(&app.name))
                    .map(move |app| (host, listing, app))
            })
            .collect();

        let mut hosts_per_name: BTreeMap<&str, BTreeSet<&HostUuid>> = BTreeMap::new();
        for (host, _, app) in &shown {
            hosts_per_name
                .entry(&app.name)
                .or_default()
                .insert(&host.uuid);
        }
        let mut uuids_per_host_name: BTreeMap<&str, BTreeSet<&HostUuid>> = BTreeMap::new();
        for (host, _, _) in &shown {
            uuids_per_host_name
                .entry(&host.name)
                .or_default()
                .insert(&host.uuid);
        }
        // Two PCs can call themselves the same (both here are "saturn" until
        // one is renamed in Moonlight), and then only the address tells them
        // apart.
        let label = |host: &PairedHost, listing: &Listing| {
            if uuids_per_host_name[host.name.as_str()].len() > 1 {
                format!("{}, {}", host.name, listing.address.host)
            } else {
                host.name.clone()
            }
        };

        let mut seen = BTreeSet::new();
        shown
            .into_iter()
            .filter_map(|(host, listing, app)| {
                let id = DesktopId::new(&host.uuid, &app.name);
                if !seen.insert(id.clone()) {
                    // Sunshine lists the same name twice: one tile.
                    return None;
                }
                let name = if hosts_per_name[app.name.as_str()].len() > 1 {
                    format!("{} ({})", app.name, label(host, listing))
                } else {
                    app.name.clone()
                };
                Some(Game {
                    id,
                    name,
                    host: host.uuid.clone(),
                    address: listing.address.clone(),
                    app: app.clone(),
                })
            })
            .collect()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Game {
    pub id: DesktopId,
    /// What Home shows.
    pub name: String,
    pub host: HostUuid,
    pub address: Address,
    pub app: App,
}

/// The desktop file name: stable for a host and app name, since Home's
/// order (emrakul's recent file) is kept by it. Sunshine's own app ids
/// change whenever an app's image or place in the list does.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct DesktopId(String);

impl DesktopId {
    fn new(host: &HostUuid, app_name: &str) -> Self {
        let mut slug = String::new();
        for c in app_name.chars().flat_map(char::to_lowercase) {
            if c.is_ascii_alphanumeric() {
                slug.push(c);
            } else if !slug.ends_with('-') {
                slug.push('-');
            }
        }
        let slug: String = slug.trim_matches('-').chars().take(32).collect();
        // The slug alone would let "V Rising" and "V-Rising" collide.
        Self(format!(
            "moonlight-{host}-{slug}-{:08x}.desktop",
            fnv1a(app_name.as_bytes())
        ))
    }

    pub fn file_name(&self) -> &str {
        &self.0
    }
}

fn fnv1a(bytes: &[u8]) -> u32 {
    bytes.iter().fold(0x811c_9dc5, |hash, &b| {
        (hash ^ u32::from(b)).wrapping_mul(0x0100_0193)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{moonlight::Addresses, sunshine::AppId};

    fn uuid(s: &str) -> HostUuid {
        HostUuid::try_from(s.to_owned()).unwrap()
    }

    fn address(host: &str) -> Address {
        Address {
            host: host.into(),
            http_port: 47989,
        }
    }

    fn host(id: &str, name: &str, at: &str) -> PairedHost {
        PairedHost {
            uuid: uuid(id),
            name: name.into(),
            addresses: Addresses {
                preferred: address(at),
                others: vec![],
            },
            server_cert: Vec::new().into(),
            hidden: BTreeSet::new(),
        }
    }

    fn listed(at: &str, apps: &[(i64, &str)]) -> Answer {
        Answer::Listed(Listing {
            address: address(at),
            apps: apps
                .iter()
                .map(|&(id, name)| App {
                    id: AppId(id),
                    name: name.into(),
                })
                .collect(),
        })
    }

    fn names(library: &Library, hosts: &[PairedHost]) -> Vec<String> {
        let mut names: Vec<_> = library.games(hosts).into_iter().map(|g| g.name).collect();
        names.sort();
        names
    }

    #[test]
    fn a_silent_host_keeps_its_games_and_an_answering_one_sets_them() {
        let hosts = [
            host("aa", "saturn", "10.0.0.23"),
            host("bb", "freja", "10.0.0.22"),
        ];
        let library = Library::default().update([
            (
                uuid("aa"),
                listed("10.0.0.23", &[(1, "Desktop"), (2, "V Rising")]),
            ),
            (
                uuid("bb"),
                listed("10.0.0.22", &[(1, "Desktop"), (3, "Sims")]),
            ),
        ]);
        assert_eq!(
            names(&library, &hosts),
            ["Desktop (freja)", "Desktop (saturn)", "Sims", "V Rising"]
        );

        // freja is switched off: everything stays.
        let library = library.update([
            (
                uuid("aa"),
                listed("10.0.0.23", &[(1, "Desktop"), (2, "V Rising")]),
            ),
            (uuid("bb"), Answer::Silent),
        ]);
        assert_eq!(
            names(&library, &hosts),
            ["Desktop (freja)", "Desktop (saturn)", "Sims", "V Rising"]
        );

        // saturn answers without V Rising: only that goes.
        let library = library.update([
            (uuid("aa"), listed("10.0.0.23", &[(1, "Desktop")])),
            (uuid("bb"), Answer::Silent),
        ]);
        assert_eq!(
            names(&library, &hosts),
            ["Desktop (freja)", "Desktop (saturn)", "Sims"]
        );

        // freja unpaired: gone from the conf, gone from Home.
        let library = library.update([(uuid("aa"), Answer::Silent)]);
        assert_eq!(names(&library, &hosts[..1]), ["Desktop"]);
    }

    #[test]
    fn a_host_never_heard_from_has_no_games() {
        let library = Library::default().update([(uuid("aa"), Answer::Silent)]);
        assert_eq!(library, Library::default());
    }

    #[test]
    fn same_named_hosts_are_told_apart_by_address() {
        let hosts = [
            host("aa", "saturn", "10.0.0.23"),
            host("bb", "saturn", "10.0.0.22"),
        ];
        let library = Library::default().update([
            (uuid("aa"), listed("10.0.0.23", &[(1, "Desktop")])),
            (uuid("bb"), listed("10.0.0.22", &[(1, "Desktop")])),
        ]);
        assert_eq!(
            names(&library, &hosts),
            ["Desktop (saturn, 10.0.0.22)", "Desktop (saturn, 10.0.0.23)"]
        );
    }

    #[test]
    fn hidden_apps_have_no_tile() {
        let mut saturn = host("aa", "saturn", "10.0.0.23");
        saturn.hidden.insert("Steam Big Picture".into());
        let library = Library::default().update([(
            uuid("aa"),
            listed("10.0.0.23", &[(1, "Desktop"), (2, "Steam Big Picture")]),
        )]);
        assert_eq!(names(&library, &[saturn]), ["Desktop"]);
    }

    #[test]
    fn desktop_ids_are_stable_and_distinct() {
        let a = DesktopId::new(&uuid("3f55"), "V Rising");
        assert_eq!(a, DesktopId::new(&uuid("3F55"), "V Rising"));
        assert!(a.file_name().starts_with("moonlight-3f55-v-rising-"));
        assert!(a.file_name().ends_with(".desktop"));
        assert_ne!(a, DesktopId::new(&uuid("3f55"), "V-Rising"));
        assert_ne!(a, DesktopId::new(&uuid("3f56"), "V Rising"));
        let odd = DesktopId::new(&uuid("3f55"), "../../Ünïcode: \"quoted\"");
        assert!(
            odd.file_name()
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '.'),
            "{odd:?}"
        );
    }
}
