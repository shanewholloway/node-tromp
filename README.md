Tromp is an asynchronous filesystem directory walking algorithm with events and accept/reject filtering, designed to be used modules like `minimatch`.

## Use

```javascript
var tromp = require('tromp')

tromp('.')
  .reject(/node_modules/)
  .on('listed', function (listing) {
    console.log(listing.inspect()) })
```

## API

### WalkRoot
Instantiate using `function tromp(path, options, callback)`,
returning an instance of `WalkRoot` extending from `EventEmitter`.

arg                   | desc
---                   | ----
`path`                | string path reference for where to start walking
`options.showHidden`  | if falsy, names beginning with `.` will be masked. default `false` 
`options.autoWalk`    | pluggable `function(entry)` called when directories are traversed; default calls `entry.walk()`
`options.schedule`    | callable to schedule functions for later execution. default `process.nextTick`
`options.tasks`       | number of concurrent filesystem operations in flight at once
`callback`            | when provided, the function is added to `.on('listed', callback)`

event             | args          | desc
-----             | ----          | ----
`'active'`        | count, delta  | When `WalkRoot` starts and stops walk a root
`'start'`         |               | Emitted when `active` is greater than 0
`'done'`          |               | Emitted when `active` returns to 0
`'listing'`       | node          | When entries have been received, but before entries have started `fs.stat`
`'listed'`        | node          | After all entries have completed `fs.stat`
`'filter'`        | entry, node   | After each `WalkEntry`'s completes `fs.stat`, but before `entry` event
`'entry'`         | entry, node   | After each `WalkEntry`'s completes `fs.stat` and is not excluded during `filter` event
`'file'`          | entry, node   | After `'entry'` event, but only emitted for files
`'dir'`           | entry, node   | After `'entry'` event, but only emitted for directories

#### `WalkRoot::walk(path)` method
Starts a new walk rooted at path, creating a `WalkListing` instance if not already in progress for that path. Emits `active` events when listings are initiated or completed.

#### `WalkRoot::filter(rx, ctx)` method
Calls `entry.filter(rx,ctx)` for each `entry:filter` event occurence

#### `WalkRoot::accept(rx, ctx)` method
Calls `entry.accept(rx,ctx)` for each `entry:filter` event occurence

#### `WalkRoot::reject(rx, ctx)` method
Calls `entry.accept(rx,ctx)` for each `entry:filter` event occurence

#### `WalkRoot::autoWalk(entry)` method
Double dispatch mechanism, defaulting to `entry.walk()`


### WalkNode
Shared context between `WalkRoot`, `WalkListing` and `WalkEntry` instances.

* `root` is the managing `WalkRoot` instance.
* `rootPath` is the path walking initiates from
* `listPath` is the directory path of the listing


### WalkListing
Encapsulates the active process of listing a directory and stating all of the entries so they can be categorized.

* `rootPath` is the path walking initiates from
* `path` is the directory path of the listing
* `relPath` is `path` as relative to `rootPath`


#### `WalkListing::select(fnList)` method
Returns all entries not already excluded matching every function in `fnList`
#### `WalkListing::selectEx(fnList)` method
Returns all entries matching every function in `fnList`

#### `WalkListing::matching(rx, opts...)` method
Invokes `select({match:rx}, opts...)`
#### `WalkListing::files(opts...)` method
Invokes `select({isFile:true}, opts...)`
#### `WalkListing::dirs(opts...)` method
Invokes `select({isDirectory:true}, opts...)`

#### `WalkListing::walk(opts...)` method
Invokes `entry.walk()` for all directories returned by `this.dirs(opts...)`

#### `WalkListing::filter(rx, ctx)` method
Invokes `entry.filter(rx, ctx)` against all listing entries.
#### `WalkListing::accept(opts...)` method
Invokes `entry.accept(rx, ctx)` against all listing entries.
#### `WalkListing::reject(opts...)` method
Invokes `entry.reject(rx, ctx)` against all listing entries.



### WalkEntry
An manipulable object representing and entry of the `WalkListing`.

* `rootPath` is the path initially responsible for listing this entry
* `path` is the resolved path this entry represents
* `relPath` is `path` as relative to `rootPath`


#### `WalkEntry::modeKey()` method
Returns a string constant depending upon the entry file mode.

#### `WalkEntry::isFile()` method
Returns `true` if the entry is a file.

#### `WalkEntry::isDirectory()` method
Returns `true` if the entry is a directory.

#### `WalkEntry::isWalkable()` method
Returns `true` if not excluded and is a directory

#### `WalkEntry::walk(force)` method
Starts a new walk using the entry's path if it is walkable. See `WalkRoot::walk`.

#### `WalkEntry::match(rx, ctx)` method
If `rx` is callable, then `return rx.call(this.name, ctx)`
Otherwise use String::match as `return this.name.match(rx)`.

#### `WalkEntry::exclude(value)` method
Mark as excluded if `!!value`, otherwise mark as included.

#### `WalkEntry::accept(rx, ctx)` method
With no parameters, marks entry as included.
Otherwise, if `match(rx, ctx)`, then `exclude(false)`

#### `WalkEntry::reject(rx, ctx)` method
With no parameters, marks entry as excluded.
Otherwise, if `match(rx, ctx)`, then `exclude(true)`

#### `WalkEntry::filter(rx, ctx)` method
Invokes `exclude(match(rx, ctx))`
