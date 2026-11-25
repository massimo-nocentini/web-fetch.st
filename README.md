# web-fetch.st

HTTP and HTTPS for Pharo 12 to 15 on WebAssembly, with the `fetch` of the browser or of node, and an adapter for Zinc.

The work is done by the WebFetchPlugin of the VM of [massimo-nocentini/pharo-vm](https://github.com/massimo-nocentini/pharo-vm) (its `docs/WebFetch.md` is the contract); the package waits as Smalltalk code does, on a semaphore, while the VM and the other processes go on.

- `WebFetch`: class-side facade (`get:`, `post:body:type:`, `request:`, `availability`, `isAvailable`, `abortAll`).
- `WebFetchRequest`: reusable request builder (`fetch`, `start`, `stream:`).
- `WebFetchCall`: one exchange and its future (`wait`, `waitTimeout:`, `response`, `whenDone:ifError:`, `abort`).
- `WebFetchResponse`: status, reason, final URL, headers, `rawContents` and decoded `contents`.
- `WebFetchBodyStream`: binary read stream over a streaming response body.
- `WebFetchZinc`: opt-in `ZnNetworkingUtils` adapter (`WebFetch-Zinc`) that routes `ZnClient`, `ZnEasy` and `asZnUrl retrieveContents` through `WebFetch`.

`WebFetch` depends on no package that is not in the image, and changes no class of it; `WebFetch-Zinc` changes no method of Zinc or Zodiac.

## Requirements

- Pharo 12, 13, 14 or 15.
- A WebAssembly Pharo VM built with `WebFetchPlugin` (Console, Notebook, World or the node VM).
- On a native VM, the packages load normally; `WebFetch availability` answers `#unavailable` and every request signals `WebFetchUnavailable`. Unit tests run natively using `WebFetchTestHost`.

## Loading

From a local checkout of `web-fetch.st`:

```smalltalk
Metacello new
	baseline: 'WebFetch';
	repository: 'tonel:///path/to/web-fetch.st/src';
	load: #( 'Core' )
```

Groups of `BaselineOfWebFetch`:

- `Core`: `WebFetch`
- `Tests`: `WebFetch-Tests` (includes `WebFetchTestHost`)
- `Zinc`: `WebFetch-Zinc`
- `ZincTests`: `WebFetch-Zinc-Tests`
- `default`: `Core` and `Tests`

From the command line, `tests/load-webfetch.st` loads the groups named in `WEB_FETCH_GROUPS` (default `'Core Tests Zinc ZincTests'`) from `WEB_FETCH_DIR` and checks for undeclared variables before saving:

```sh
WEB_FETCH_DIR=/path/to/web-fetch.st \
pharo --headless Pharo.image --no-default-preferences st --save --quit tests/load-webfetch.st
```

## API

### Availability and simple requests

```smalltalk
WebFetch availability
"=> #ready (or #off, or #unavailable)"

WebFetch isAvailable
"=> true"

(WebFetch get: 'https://api.github.com/zen') contents

WebFetch post: url body: '{"a":1}' type: 'application/json'
```

An HTTP error status (such as 404 or 500) is returned as a `WebFetchResponse` whose `isSuccess` is `false`.

`response contents` decodes textual content types (`text/*`, `application/json`, `*+json`, `application/xml`, `*+xml`, `application/javascript`, `application/x-javascript`, `application/ecmascript`) using the `Content-Type` charset (UTF-8 by default, stripping a leading UTF-8 BOM) and returns `rawContents` (`ByteArray`) for binary types or undecodable bytes.

### Requests with options

`WebFetchRequest` is reusable: starting or fetching it never mutates it.

```smalltalk
| req resp |
req := (WebFetch request: 'https://example.org/items/1')
	method: #PUT;
	headerAt: 'X-Token' put: 'abc';
	body: 'payload';
	timeout: 10 seconds;
	maximumBodySize: 10e6;
	dontFollowRedirects;
	yourself.
resp := req fetch.
resp status.
resp headerAt: 'Content-Type' ifAbsent: [ '' ].
resp headersDo: [ :name :value | ... ].
```

`headerAt:put:` replaces case-insensitively while preserving header order. A `String` body without an explicit `Content-Type` header is sent as UTF-8 with `Content-Type: text/plain;charset=UTF-8`; a `ByteArray` body adds no `Content-Type`.

### Asynchronous calls and futures

```smalltalk
| call |
call := (WebFetch request: url) start.
call isDone.
call waitTimeout: 5 seconds.
call response contents.
```

`whenDone:ifError:` forks one process at the caller's priority (`Processor activePriority`) and evaluates the blocks outside its own error handler:

```smalltalk
call := (WebFetch request: url) start.
call
	whenDone: [ :resp | UIManager default defer: [ ... ] ]
	ifError: [ :err | UIManager default defer: [ ... ] ].
```

`call abort` cancels a single call; `WebFetch abortAll` aborts all open calls.

TaskIt `future` works without extra glue on Pharo 12 to 15:

```smalltalk
([ WebFetch get: url ] future) synchronizeTimeout: 5 seconds
```

### Streaming

`stream:` opens a `WebFetchBodyStream` (a binary read stream with a 1 MiB back-pressure window, not bounded by `maximumBodySize`), passes it to the block, and closes the call when the block returns or unwinds:

```smalltalk
(WebFetch request: url) stream: [ :stream |
	stream response status.
	stream peek.
	stream next.
	stream next: 1024.
	stream upToEnd ]
```

`WebFetchBodyStream` also understands `atEnd`, `readInto:startingAt:count:`, `do:`, `isBinary`, `isStream` and `close`. Closing before EOF aborts the request and subsequent reads signal `WebFetchAborted`; closing after EOF leaves `next` answering `nil`.

### Errors

All errors inherit from `WebFetchError` and carry a `kind` symbol:

- `WebFetchUnavailable` (`#unavailable`), subclass `WebFetchNetworkOff` (`#off`)
- `WebFetchBadRequest` (`#request`, `#redirect`)
- `WebFetchNetworkError` (`#network`, `#body`)
- `WebFetchTimeout` (`#timeout`)
- `WebFetchAborted` (`#aborted`)
- `WebFetchTooLarge` (`#tooLarge`)
- `WebFetchTooManyOpen` (`#tooManyOpen`)
- `WebFetchInCallback` (`#inCallback`)
- `WebFetchSessionEnded` (`#sessionEnded`)

## Waiting, Stop, UI process, sessions and callbacks

- **Stop and unwinding**: `fetch`, `get:`, `post:body:type:`, `stream:`, `wait`, `response` and `waitForHead` abort the host request when curtailed (Stop in Console/Notebook/World, process `terminate`, or exception unwinding). `waitTimeout:` and `whenDone:ifError:` do not abort on curtailment or timeout expiry.
- **UI process**: waiting messages (`fetch`, `get:`, `post:body:type:`, `stream:`, `wait`, `response`) freeze the world while waiting, as a socket does natively; Stop in the world opens a debugger on the process, and the request stays open until the debugger is closed. UI tools should use `start` with `whenDone:ifError:` and `UIManager default defer:`.
- **Sessions**: `WebFetchCall` registers with `SessionManager`. When a saved image resumes in a new session, in-progress calls fail with `WebFetchSessionEnded` and wake any waiting processes without hanging. Calls that already finished keep their cached response.
- **FFI callbacks**: starting and reading work inside an FFI callback; blocking waits check `WebFetchHost >> mayWait` (`primitiveMayWait`) and signal `WebFetchInCallback` immediately (`fetch` and `stream:` fail before starting any request).

## Limits and defaults

- Default timeout: `60 seconds` for `fetch`, `get:` and `post:body:type:`; none for `start` and `stream:`. Explicit `timeout: nil` or `timeout: Duration zero` disables the timeout.
- Default `maximumBodySize`: 64 MiB (valid range `0` to `2^31 - 2`); applies to `fetch` and `start`, not `stream:`.
- Maximum request body: 64 MiB; maximum encoded request head: 1 MiB.
- Streaming window: 1 MiB.
- Maximum concurrent open requests per VM: 64 (the 65th signals `WebFetchTooManyOpen`).
- In a browser, other origins answer only with CORS, at most six requests at a time go to a host over HTTP/1.1, and Chromium lets simultaneous GETs of one URL wait for one another (its cache).
- The user can turn the network off (Settings of the pages; `PHARO_WASM_NETWORK=0` in node): `availability` is then `#off`, a start signals `WebFetchNetworkOff`, and the open calls fail with it.

## Zinc adapter (`WebFetch-Zinc`)

Loading `WebFetch-Zinc` does not install it. Enable or disable it explicitly:

```smalltalk
WebFetchZinc install.
WebFetchZinc isInstalled. "=> true"
ZnClient new get: 'https://api.github.com/zen'.
WebFetchZinc uninstall.
```

`WebFetchZinc` sets `ZnNetworkingUtils default:` to a `WebFetchNetworkingUtils` that returns a `WebFetchSocketStream` (`< ZdcSocketStream`) for `http` and `https` whenever `WebFetch availability ~= #unavailable` (including `#off`, so disabled network produces a clean error). On native VMs, and for `ws`/`wss` or server sockets, everything forwards to the previous `ZnNetworkingUtils` unchanged. Unloading `WebFetch-Zinc` uninstalls it automatically.

Differences from a native socket:

- Redirects are followed by the host: Zinc sees the final response with `X-WebFetch-Url` set to the final URL, `request url` stays the first URL, and `maxNumberOfRedirects` does not apply. With `dontFollowRedirects`, node returns the 3xx response while browsers fail.
- No cookies, no image HTTP proxy, and no client certificates; TLS verification is performed by the host.
- `Accept-Encoding`, `Host`, `Connection` and (in browsers) `User-Agent` are controlled by the host; compressed answers arrive decompressed without `Content-Length`.
- In browsers, `Authorization`, JSON posts and custom headers trigger a CORS preflight, and CORS/network refusals carry no specific reason. GitHub API and raw endpoints allow browser CORS; `codeload.github.com` zip archives do not.
- Request bodies are gathered whole before sending (up to 64 MiB); `GET` with a body is refused.
- One exchange per connection (`isConnected` becomes `false` after the response). Streaming clients (`streaming: true`) or clients that fail mid-read (`ZnEntityTooLarge`) must be closed (`client close`), as with a socket.
- Errors: timeouts map to `ConnectionTimedOut`; network failures and network-off map to `WebFetchZnNetworkError` (`< NetworkError`); other `WebFetchError`s pass through without triggering Zinc retries.

## Tests

Native unit tests run without a WebAssembly VM using `WebFetchTestHost`. Live tests (`WebFetchLiveTest`) run on a WebAssembly VM against `tests/wasm/lib/fetch-http.mjs` from the VM repository:

```sh
node /path/to/pharo-vm/tests/wasm/lib/fetch-http.mjs
# prints http://127.0.0.1:<port>
WEB_FETCH_SERVER=http://127.0.0.1:<port> \
pharo --headless Pharo.image --no-default-preferences st --quit tests/run-webfetch.st
```

`tests/run-webfetch.st` also reads the server URL from a `webfetch.lane` file in the working directory when `WEB_FETCH_SERVER` is not set. Without a server URL, or off WebAssembly, live tests skip themselves.

## License

MIT (see `LICENSE`).
