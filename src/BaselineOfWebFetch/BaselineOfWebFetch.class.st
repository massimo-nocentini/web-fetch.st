"
I am the baseline of WebFetch: HTTP(S) fetch for Pharo 12 to 15 on WebAssembly via `WebFetchPlugin`, with an optional Zinc adapter.

Groups:

- `Core`: `WebFetch` (no external dependency);
- `Tests`: `WebFetch-Tests` (unit tests with `WebFetchTestHost`, native and live tests);
- `Zinc`: `WebFetch-Zinc` (optional `ZnNetworkingUtils` adapter);
- `ZincTests`: `WebFetch-Zinc-Tests`;
- `WebSocket`: `WebFetch-WebSocket` (WebSocket client connections, by `WebSocketPlugin`);
- `WebSocketTests`: `WebFetch-WebSocket-Tests`;
- `default`: `Core` and `Tests`.
"
Class {
	#name : 'BaselineOfWebFetch',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfWebFetch',
	#package : 'BaselineOfWebFetch'
}

{ #category : 'baselines' }
BaselineOfWebFetch >> baseline: spec [
	<baseline>
	spec for: #common do: [
		spec
			package: 'WebFetch';
			package: 'WebFetch-Tests' with: [ spec requires: #( 'WebFetch' ) ];
			package: 'WebFetch-Zinc' with: [ spec requires: #( 'WebFetch' ) ];
			package: 'WebFetch-Zinc-Tests' with: [ spec requires: #( 'WebFetch-Zinc' 'WebFetch-Tests' ) ];
			package: 'WebFetch-WebSocket' with: [ spec requires: #( 'WebFetch' ) ];
			package: 'WebFetch-WebSocket-Tests' with: [ spec requires: #( 'WebFetch-WebSocket' 'WebFetch-Tests' ) ].
		spec
			group: 'Core' with: #( 'WebFetch' );
			group: 'Tests' with: #( 'WebFetch-Tests' );
			group: 'Zinc' with: #( 'WebFetch-Zinc' );
			group: 'ZincTests' with: #( 'WebFetch-Zinc-Tests' );
			group: 'WebSocket' with: #( 'WebFetch-WebSocket' );
			group: 'WebSocketTests' with: #( 'WebFetch-WebSocket-Tests' );
			group: 'default' with: #( 'Core' 'Tests' ) ]
]
