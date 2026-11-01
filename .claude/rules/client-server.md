---
paths:
  - "Sources/Cli/**"
  - "Sources/AppBundle/server.swift"
  - "Sources/AppBundle/subscriptions.swift"
  - "Sources/AppBundle/model/ServerEvent.swift"
  - "Sources/Common/model/clientServer.swift"
  - "Sources/Common/util/NWConnectionEx.swift"
---

Before changing these files, read [Client-server protocol](../../docs/architecture/client-server.md).

The aerospace CLI to AeroSpace.app socket protocol (handshake, framing, request/answer, subscribe streaming) and the client process, for sessions changing either end or chasing CLI latency.
