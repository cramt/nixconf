//! emrakul-games: a Home tile for every app on every Sunshine host this
//! Moonlight is paired with. Reads the paired hosts and the client identity
//! from Moonlight.conf, asks each host for its app list and box art, and
//! writes one desktop entry per app into
//! `$XDG_STATE_HOME/emrakul-games/share/applications`, a data dir emrakul's
//! Home reads. A host paired later by PIN gets its tiles on the next run.

mod entry;
mod library;
mod moonlight;
mod qsettings;
mod sunshine;

use std::{
    collections::BTreeSet,
    path::{Path, PathBuf},
    process::ExitCode,
};

use anyhow::Context;
use clap::Parser;

use crate::{
    entry::{Commands, Icon},
    library::{Answer, Library, Listing},
    moonlight::{Conf, HostUuid, Identity, PairedHost},
    sunshine::Client,
};

#[derive(Parser)]
struct Args {
    /// Run as `<stream> <address> <app name>` to stream a game.
    #[arg(long)]
    stream: PathBuf,
    /// Run as `<quit> <address>` to end the game when going Home.
    #[arg(long)]
    quit: PathBuf,
    /// The tile's icon for a game without usable box art.
    #[arg(long)]
    fallback_icon: PathBuf,
    /// Moonlight.conf. Moonlight's own by default.
    #[arg(long)]
    conf: Option<PathBuf>,
    /// Where the library, the box art and the desktop entries go.
    /// `$XDG_STATE_HOME/emrakul-games` by default.
    #[arg(long)]
    state: Option<PathBuf>,
}

fn main() -> ExitCode {
    match run(Args::parse()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("emrakul-games: {err:#}");
            ExitCode::FAILURE
        }
    }
}

fn run(args: Args) -> anyhow::Result<()> {
    let conf_path = args.conf.map_or_else(moonlight::default_path, Ok)?;
    let state = match args.state {
        Some(state) => state,
        None => env_dir("XDG_STATE_HOME")
            .or_else(|| Some(env_dir("HOME")?.join(".local/state")))
            .context("neither XDG_STATE_HOME nor HOME is set")?
            .join("emrakul-games"),
    };
    // Nothing is touched until the conf has parsed: a missing or broken one
    // must not read as "every host unpaired" and empty Home of games.
    let conf = Conf::parse(
        &std::fs::read_to_string(&conf_path)
            .with_context(|| format!("reading {}", conf_path.display()))?,
    )
    .with_context(|| format!("parsing {}", conf_path.display()))?;

    let library_path = state.join("library.json");
    let library = load_library(&library_path);
    let art = state.join("art");

    let answers: Vec<(HostUuid, Answer)> = std::thread::scope(|scope| {
        let asking: Vec<_> = conf
            .hosts
            .iter()
            .map(|host| {
                let art = art.join(host.uuid.to_string());
                let identity = &conf.identity;
                scope.spawn(move || ask(identity, host, &art))
            })
            .collect();
        conf.hosts
            .iter()
            .zip(asking)
            .map(|(host, asking)| (host.uuid.clone(), asking.join().unwrap_or(Answer::Silent)))
            .collect()
    });
    let answered: BTreeSet<HostUuid> = answers
        .iter()
        .filter(|(_, a)| matches!(a, Answer::Listed(_)))
        .map(|(uuid, _)| uuid.clone())
        .collect();

    let library = library.update(answers);
    write_atomic(&library_path, serde_json::to_vec_pretty(&library)?)?;
    for host in &conf.hosts {
        let apps = library.listing(&host.uuid).map_or(0, |l| l.apps.len());
        if answered.contains(&host.uuid) {
            eprintln!("{}: {apps} apps", host.name);
        } else {
            eprintln!(
                "{}: no answer, keeping the {apps} apps it last listed",
                host.name
            );
        }
    }

    let games = library.games(&conf.hosts);
    let commands = Commands {
        stream: &args.stream,
        quit: &args.quit,
    };
    let applications = state.join("share/applications");
    std::fs::create_dir_all(&applications)?;
    let mut written = BTreeSet::new();
    for game in &games {
        let art_path = art
            .join(game.host.to_string())
            .join(format!("{}.png", game.app.id.0));
        let icon = match std::fs::read(&art_path)
            .ok()
            .and_then(|png| entry::art_brand(&png))
        {
            Some(brand) => Icon::Art {
                path: &art_path,
                brand,
            },
            None => Icon::Fallback(&args.fallback_icon),
        };
        let text = entry::render(game, &commands, &icon);
        let path = applications.join(game.id.file_name());
        // Unchanged entries stay untouched, so Home has nothing to re-read.
        if std::fs::read_to_string(&path).ok().as_deref() != Some(text.as_str()) {
            write_atomic(&path, text)?;
        }
        written.insert(game.id.file_name().to_owned());
    }
    remove_unlisted(&applications, |name| {
        name.ends_with(".desktop") && !written.contains(name)
    })?;
    prune_art(&art, &library, &conf.hosts)?;
    eprintln!("{} games on Home", games.len());
    Ok(())
}

/// The host's app list, from the first of its addresses that answers, with
/// box art fetched for apps that have none yet.
fn ask(identity: &Identity, host: &PairedHost, art: &Path) -> Answer {
    let client = match Client::new(identity, host) {
        Ok(client) => client,
        Err(err) => {
            eprintln!("{}: {err:#}", host.name);
            return Answer::Silent;
        }
    };
    for address in host.addresses.iter() {
        let apps = match client.apps(address) {
            Ok(apps) => apps,
            Err(err) => {
                eprintln!("{} at {address}: {err:#}", host.name);
                continue;
            }
        };
        for app in &apps {
            let path = art.join(format!("{}.png", app.id.0));
            if path.exists() {
                continue;
            }
            match client
                .box_art(address, app.id)
                .and_then(|png| write_atomic(&path, png))
            {
                Ok(()) => {}
                Err(err) => eprintln!("{}: box art for {}: {err:#}", host.name, app.name),
            }
        }
        return Answer::Listed(Listing {
            address: address.clone(),
            apps,
        });
    }
    Answer::Silent
}

/// A missing library is a first run. An unreadable one costs the offline
/// hosts their tiles until they answer again, which beats not running.
fn load_library(path: &Path) -> Library {
    match std::fs::read(path) {
        Ok(json) => serde_json::from_slice(&json).unwrap_or_else(|err| {
            eprintln!("{}: {err}, starting over", path.display());
            Library::default()
        }),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Library::default(),
        Err(err) => {
            eprintln!("{}: {err}, starting over", path.display());
            Library::default()
        }
    }
}

/// Art for hosts and apps the library no longer has.
fn prune_art(art: &Path, library: &Library, hosts: &[PairedHost]) -> anyhow::Result<()> {
    let Ok(dirs) = std::fs::read_dir(art) else {
        return Ok(());
    };
    for dir in dirs.flatten() {
        let name = dir.file_name().to_string_lossy().into_owned();
        let listing = hosts
            .iter()
            .find(|h| h.uuid.to_string() == name)
            .and_then(|h| library.listing(&h.uuid));
        match listing {
            Some(listing) => {
                let keep: BTreeSet<String> = listing
                    .apps
                    .iter()
                    .map(|a| format!("{}.png", a.id.0))
                    .collect();
                remove_unlisted(&dir.path(), |file| !keep.contains(file))?;
            }
            None => std::fs::remove_dir_all(dir.path())?,
        }
    }
    Ok(())
}

fn remove_unlisted(dir: &Path, stale: impl Fn(&str) -> bool) -> anyhow::Result<()> {
    for file in std::fs::read_dir(dir)?.flatten() {
        if stale(&file.file_name().to_string_lossy()) {
            std::fs::remove_file(file.path())
                .with_context(|| format!("removing {}", file.path().display()))?;
        }
    }
    Ok(())
}

/// Written aside and renamed over, so Home never reads half an entry. The
/// aside name doesn't end in .desktop, so Home doesn't read it at all.
fn write_atomic(path: &Path, contents: impl AsRef<[u8]>) -> anyhow::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let mut partial = path.as_os_str().to_owned();
    partial.push(".partial");
    std::fs::write(&partial, contents)
        .and_then(|()| std::fs::rename(&partial, path))
        .with_context(|| format!("writing {}", path.display()))
}

/// An absolute path from the environment; the basedir spec says relative
/// ones are invalid.
fn env_dir(var: &str) -> Option<PathBuf> {
    std::env::var_os(var)
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
}
