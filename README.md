# bwg-mikrotik

`bwg-mikrotik` packages a customized Amnezia WireGuard stack for constrained and unstable network environments. It combines the `amnezia-wg-tools` userspace utilities with the `amneziawg-go` dataplane so the runtime can keep a WireGuard-compatible workflow while applying additional transport hardening and operational safeguards.

At a high level, this build focuses on making tunnel traffic less predictable to simple DPI heuristics and more resilient under packet loss, route asymmetry, and endpoint instability. The project also emphasizes observability and controlled failover behavior so operators can monitor tunnel health and recover connectivity quickly, without exposing implementation or deployment-specific configuration in this repository.

Supported features:
- **Dual-port architecture (control/data separation)**  
  Handshake/control messages and encrypted transport packets can be handled on distinct paths, improving flexibility for routing policy and resilience under targeted path disruption.
- **Endpoint-aware session behavior**  
  Peer endpoint handling tracks path state and supports independent treatment of control and data flows, which helps maintain connectivity during endpoint shifts and roaming-like transitions.
- **Transport header and traffic-shape hardening**  
  The stack supports protocol-level obfuscation techniques that reduce stable wire fingerprints and make straightforward signature matching less effective.
- **Adjustable handshake/transport camouflage primitives**  
  The underlying AWG model supports shaping elements such as padding, header variation, and optional pre-handshake noise/signature traffic to diversify observable flow patterns.
- **QUIC-style mimicry pipeline (advanced mode)**  
  Changelog-tracked capabilities include endpoint-level QUIC wrapping, realistic-looking packet progression, and protocol-specific send/receive adaptation aimed at blending with common QUIC traffic profiles.
- **Active probe-response behavior (advanced mode)**  
  The architecture includes probe-handling mechanisms for suspicious inbound traffic patterns, reducing silent-drop fingerprints in hostile network environments.
- **NAT/CGNAT liveness maintenance**  
  Keepalive-oriented behavior is designed to keep mappings warm on unstable links and reduce idle path collapse in mobile and lossy upstream scenarios.
- **DNS-shaped exchange channel for control/telemetry workflows**  
  The design includes DNS-format packet exchange patterns for keepalive and lightweight signaling/metrics transfer, so auxiliary traffic can resemble regular resolver/query behavior instead of custom tunnel-control framing.
- **Loss-aware endpoint strategy under asymmetry**  
  Endpoint selection can incorporate loss/quality signals and asymmetric path behavior, preferring healthier channels when multiple candidates exist.
- **Operational telemetry and health visibility**  
  Runtime counters and status outputs are available for troubleshooting and path-quality observation; container health checks also validate that peers/handshakes are present.

