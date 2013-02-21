Tromp is an asynchronous filesystem directory walking algorithm with events and accept/reject filtering. For use with `minimatch` or other filtering tools.

## Use

```javascript

var tromp = require('tromp')

tromp('.')
  .reject(/node_modules/)
  .on('listed', function (node) {
    console.log({
      base: node.base(),
      files: node.files(),
      dirs: node.dirs()})
  })

```

## API

### `class WalkRoot`
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

event       | args          | desc
-----       | ----          | ----
`'active'`  | count, delta  | When `WalkRoot` starts and stops walk a root
`'listing'` | node          | When entries have been received, but before entries have started `fs.stat`
`'listed'`  | node          | After all entries have completed `fs.stat`
`'entry'`   | entry, node   | After each `WalkEntry`'s completes `fs.stat`
`'file'`    | entry, node   | After `'entry'` event, but filtered for files
`'dir'`     | entry, node   | After `'entry'` event, but filtered for directories

#### `WalkRoot::walk(path)`
Starts a new walk rooted at path, creating a `WalkListing` instance if not already in progress for that path. Emits `active` events when listings are initiated or completed.

#### `WalkRoot::filter(rx, ctx)`
Calls `entry.filter(rx,ctx)` for each `entry` event occurance

#### `WalkRoot::accept(rx, ctx)`
Calls `entry.accept(rx,ctx)` for each `entry` event occurance

#### `WalkRoot::reject(rx, ctx)`
Calls `entry.accept(rx,ctx)` for each `entry` event occurance

#### `WalkRoot::autoWalk(entry)`
Double dispatch mechanism, defaulting to `entry.walk()`



### `class WalkListing`
Encapsulates the active process of listing a directory and stating all of the entries so they can be categorized.

property  | description
----------|-------------
listing   | `this`
path      | string path being listed
root      | connected `WalkRoot` instance via `listing` property
rootPath  | path initially responsible for causing this listing
relPath   | `path.relative(this.rootPath, this.path)`


#### `WalkListing::select(fnList)`
Returns all entries not already excluded matching every function in `fnList`
#### `WalkListing::selectEx(fnList)`
Returns all entries matching every function in `fnList`

#### `WalkListing::matching(rx, opts...)`
Invokes `select({match:rx}, opts...)`
#### `WalkListing::files(opts...)`
Invokes `select({isFile:true}, opts...)`
#### `WalkListing::dirs(opts...)`
Invokes `select({isDirectory:true}, opts...)`

#### `WalkListing::walk(opts...)`
Invokes `entry.walk()` for all directories returned by `this.dirs(opts...)`

#### `WalkListing::filter(rx, ctx)`
Invokes `entry.filter(rx, ctx)` against all listing entries.
#### `WalkListing::accept(opts...)`
Invokes `entry.accept(rx, ctx)` against all listing entries.
#### `WalkListing::reject(opts...)`
Invokes `entry.reject(rx, ctx)` against all listing entries.



### `class WalkEntry`
An manipulable object representing and entry of the `WalkListing`.

property  | description
----------|-------------
name      | entry basename
listing   | connected `WalkListing` instance
path      | `path.resolve(this.listing.path, this.name)`
root      | connected `WalkRoot` instance via `listing` property
rootPath  | path initially responsible for causing this listing
relPath   | `path.relative(this.rootPath, this.path)`

#### `WalkEntry::modeKey()`
Returns a string constant depending upon the entry file mode.

#### `WalkEntry::isFile()`
Returns `true` if the entry is a file.

#### `WalkEntry::isDirectory()`
Returns `true` if the entry is a directory.

#### `WalkEntry::isWalkable()`
Returns `true` if not excluded and is a directory

#### `WalkEntry::walk(force)`
Starts a new walk using the entry's path if it is walkable. See `WalkRoot::walk`.

#### `WalkEntry::match(rx, ctx)`
If `rx` is callable, then `return rx.call(this.name, ctx)`
Otherwise use String::match as `return this.name.match(rx)`.

#### `WalkEntry::exclude(value)`
Mark as excluded if `!!value`, otherwise mark as included.

#### `WalkEntry::accept(rx, ctx)`
With no parameters, marks entry as included.
Otherwise, if `match(rx, ctx)`, then `exclude(false)`

#### `WalkEntry::reject(rx, ctx)`
With no parameters, marks entry as excluded.
Otherwise, if `match(rx, ctx)`, then `exclude(true)`

#### `WalkEntry::filter(rx, ctx)`
Invokes `exclude(match(rx, ctx))`
