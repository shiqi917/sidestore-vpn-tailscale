use clap::Parser;
use smoltcp::wire::{Ipv4Address, Ipv4Packet};
use std::io::{Read, Write};
use tun::AbstractDevice;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Name of the TUN interface
    #[arg(short, long, default_value = "sidestore")]
    tun_name: String,

    /// Address to reflect. Packets destined to this address get src/dst
    /// swapped and bounced back to the sender. For SideStore nightly over
    /// Tailscale, set this to <device tailscale IP> + 1 (minimuxer derives
    /// its tunnel peer as iface IP + 1 on a /32 utun).
    #[arg(short, long, env = "REFLECT_ADDR", default_value = "10.7.0.1")]
    reflect_addr: Ipv4Address,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();
    let reflect_addr = args.reflect_addr;

    // Set up Ctrl+C handler to exit immediately
    ctrlc::set_handler(|| {
        std::process::exit(0);
    })?;

    let mut config = tun::Configuration::default();
    config.tun_name(&args.tun_name);
    config.up();

    let mut dev = tun::create(&config)?;
    dev.set_address(std::net::IpAddr::V4(Ipv4Address::new(10, 7, 0, 0)))
        .expect("Failed to set interface address");
    dev.set_destination(std::net::IpAddr::V4(reflect_addr))
        .expect("Failed to set destination address");
    dev.enabled(true).expect("Failed to enable interface");

    println!(
        "TUN device \"{}\" is up, reflecting {}",
        args.tun_name, reflect_addr
    );

    let mut buf = [0u8; 1504]; // MTU of 1500 + 4 bytes for header

    loop {
        let n = dev.read(&mut buf)?;
        let packet_buf = &mut buf[..n];

        // Parse the packet as an IPv4 packet.
        if let Ok(mut ipv4_packet) = Ipv4Packet::new_checked(packet_buf) {
            let dst_addr = ipv4_packet.dst_addr();

            if dst_addr == reflect_addr {
                // Swap source and destination addresses
                let src_addr = ipv4_packet.src_addr();
                ipv4_packet.set_dst_addr(src_addr);
                ipv4_packet.set_src_addr(dst_addr);

                // The checksum is automatically updated by the setters.
                dev.write(ipv4_packet.into_inner())?;
            }
        }
        // Other packets are dropped.
    }
}
