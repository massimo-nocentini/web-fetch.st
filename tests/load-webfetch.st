"load-webfetch.st - load WebFetch with Metacello from a checkout of this repository

	WEB_FETCH_DIR=<the checkout> pharo --headless X.image --no-default-preferences st --save --quit load-webfetch.st

 WEB_FETCH_DIR     the checkout; by default the directory above the one of this file, when the
                   command line names it
 WEB_FETCH_GROUPS  the groups of BaselineOfWebFetch to load, separated by blanks
                   (by default 'Core Tests Zinc ZincTests')

 It prints 'WebFetch: loaded #(<groups>), <availability>' and exits with status 1, before the image is
 saved, when the load fails or a method of a WebFetch package uses an undeclared variable."

| environment out lineEnd fail directory repository groups packages undeclared |
environment := OSEnvironment current.
out := Stdio stdout.
lineEnd := OSPlatform current lineEnding.
fail := [ :message |
	Stdio stderr nextPutAll: 'load-webfetch: '; nextPutAll: message; nextPutAll: lineEnd; flush.
	Smalltalk exitFailure ].
directory := (environment at: 'WEB_FETCH_DIR' ifAbsent: [ nil ])
	ifNil: [
		(CommandLineArguments new arguments
			detect: [ :each | each endsWith: 'load-webfetch.st' ]
			ifNone: [ fail value: 'WEB_FETCH_DIR is not set' ]) asFileReference asAbsolute parent parent ]
	ifNotNil: [ :path | path asFileReference asAbsolute ].
repository := directory / 'src'.
(repository / 'BaselineOfWebFetch') isDirectory ifFalse: [ fail value: 'no ' , (repository / 'BaselineOfWebFetch') fullName ].
groups := ((environment at: 'WEB_FETCH_GROUPS' ifAbsent: [ 'Core Tests Zinc ZincTests' ]) substrings: ' ') asArray.

[ Metacello new
	baseline: 'WebFetch';
	repository: 'tonel://' , repository fullName;
	load: groups ]
	on: Error
	do: [ :error | fail value: 'loading ' , groups printString , ': ' , error description ].

packages := (PackageOrganizer default packageNames select: [ :each | each beginsWith: 'WebFetch' ]) asSortedCollection asArray.
undeclared := (packages flatCollect: [ :each | each asPackage methods ]) select: [ :method | method usesUndeclareds ].
undeclared ifNotEmpty: [
	fail value: 'undeclared variables in ' , (undeclared collect: [ :method | method printString ]) asArray printString ].
out
	nextPutAll: 'WebFetch: loaded '; nextPutAll: groups printString;
	nextPutAll: ', '; nextPutAll: (Smalltalk globals at: #WebFetch) availability;
	nextPutAll: lineEnd; flush.
