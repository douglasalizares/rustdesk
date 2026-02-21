#![cfg_attr(
    all(not(debug_assertions), target_os = "windows", not(feature = "cli")),
    windows_subsystem = "windows"
)]

use librustdesk::*;

#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
fn main() {
    if !common::global_init() {
        eprintln!("Global initialization failed.");
        return;
    }
    common::test_rendezvous_server();
    common::test_nat_type();
    common::global_clean();
}

#[cfg(not(any(
    target_os = "android",
    target_os = "ios",
    feature = "cli",
    feature = "flutter"
)))]
fn main() {
    #[cfg(all(windows, not(feature = "inline")))]
    unsafe {
        winapi::um::shellscalingapi::SetProcessDpiAwareness(2);
    }
    if let Some(args) = crate::core_main::core_main().as_mut() {
        ui::start(args);
    }
    common::global_clean();
}

#[cfg(feature = "cli")]
fn main() {
    if !common::global_init() {
        return;
    }
    use clap::{Arg, Command};
    use hbb_common::log;
    let matches = Command::new("rustdesk")
        .version(crate::VERSION)
        .author("Purslane Ltd<info@rustdesk.com>")
        .about("RustDesk command line tool")
        .arg(Arg::new("port-forward")
            .short('p')
            .long("port-forward")
            .num_args(1)
            .help("Format: remote-id:local-port:remote-port[:remote-host]"))
        .arg(Arg::new("connect")
            .short('c')
            .long("connect")
            .num_args(1)
            .help("test only"))
        .arg(Arg::new("password")
            .long("password")
            .num_args(1)
            .help("Password for the remote peer (avoids interactive prompt)"))
        .arg(Arg::new("id-server")
            .long("id-server")
            .num_args(1)
            .help("Custom rendezvous/ID server address (e.g., myserver.com or myserver.com:21116)"))
        .arg(Arg::new("key")
            .short('k')
            .long("key")
            .num_args(1))
        .arg(Arg::new("server")
            .short('s')
            .long("server")
            .action(clap::ArgAction::SetTrue)
            .help("Start server"))
        .get_matches();
    use hbb_common::{config, config::LocalConfig, env_logger::*};
    init_from_env(Env::default().filter_or(DEFAULT_FILTER_ENV, "info"));
    // Set custom rendezvous server if provided via --id-server
    if let Some(id_server) = matches.get_one::<String>("id-server") {
        let server = hbb_common::socket_client::check_port(id_server, config::RENDEZVOUS_PORT);
        *config::EXE_RENDEZVOUS_SERVER.write().unwrap() = server.clone();
        eprintln!("[DEBUG] Using custom ID server: {}", server);
    }
    if let Some(p) = matches.get_one::<String>("port-forward") {
        eprintln!("[DEBUG] port-forward arg received: {}", p);
        let options: Vec<String> = p.split(":").map(|x: &str| x.to_owned()).collect();
        if options.len() < 3 {
            eprintln!("[ERROR] Wrong port-forward options");
            return;
        }
        let mut port = 0;
        if let Ok(v) = options[1].parse::<i32>() {
            port = v;
        } else {
            eprintln!("[ERROR] Wrong local-port");
            return;
        }
        let mut remote_port = 0;
        if let Ok(v) = options[2].parse::<i32>() {
            remote_port = v;
        } else {
            eprintln!("[ERROR] Wrong remote-port");
            return;
        }
        let mut remote_host = "localhost".to_owned();
        if options.len() > 3 {
            remote_host = options[3].clone();
        }
        eprintln!("[DEBUG] Connecting to {} port {} -> {}:{}", options[0], port, remote_host, remote_port);
        common::test_rendezvous_server();
        common::test_nat_type();
        let key = matches.get_one::<String>("key").map(|s| s.as_str()).unwrap_or("").to_owned();
        let token = LocalConfig::get_option("access_token");
        let password = matches.get_one::<String>("password").cloned().unwrap_or_default();
        eprintln!("[DEBUG] Starting port forward...");
        cli::start_one_port_forward(
            options[0].clone(),
            password,
            port,
            remote_host,
            remote_port,
            key,
            token,
        );
    } else if let Some(p) = matches.get_one::<String>("connect") {
        common::test_rendezvous_server();
        common::test_nat_type();
        let key = matches.get_one::<String>("key").map(|s| s.as_str()).unwrap_or("").to_owned();
        let token = LocalConfig::get_option("access_token");
        cli::connect_test(p, key, token);
    } else if matches.get_flag("server") {
        log::info!("id={}", hbb_common::config::Config::get_id());
        crate::start_server(true, false);
    } else {
        eprintln!("[DEBUG] No matching command found. Use --help for usage.");
    }
    common::global_clean();
}
