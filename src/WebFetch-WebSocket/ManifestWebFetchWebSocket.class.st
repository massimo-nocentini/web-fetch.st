"
`WebFetch-WebSocket` opens WebSocket client connections from Pharo 12 to 15 on WebAssembly with the `WebSocket` of the host (of the worker in a browser, of node in the node VM), by the `WebSocketPlugin` of the VM, whose contract is `docs/WebSocket.md` of the VM. It needs `WebFetch` (its errors, and `WebFetchCall class >> checkMayWait:`), and changes no class of it.

Off WebAssembly, or on a VM without the plugin, `WebFetchWebSocket availability` answers `#unavailable`, and `start` and `connect:` signal `WebFetchUnavailable`; `WebFetchWebSocketHost default:` takes the fake host of the tests.

## Tags

- `Core`: `WebFetchWebSocket`, `WebFetchWebSocketHost`, `WebFetchWebSocketCloser`.
- `Errors`: `WebFetchWebSocketClosed`, `WebFetchWebSocketOverflow`.
"
Class {
	#name : 'ManifestWebFetchWebSocket',
	#superclass : 'PackageManifest',
	#category : 'WebFetch-WebSocket-Manifest',
	#package : 'WebFetch-WebSocket',
	#tag : 'Manifest'
}
