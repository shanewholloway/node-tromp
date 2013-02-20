fs = require 'fs'
path = require 'path'
events = require 'events'

class WalkFuncComp extends Array
  constructor: -> super

  any: () -> @anyEx(arguments)
  anyEx: (optList) ->
    fnList = []
    for opt in optList
      @addFilterFn opt
    return (e)=> @some (fn)-> fn.call(this, e)

  all: () -> @allEx(arguments)
  allEx: (optList) ->
    for opt in optList
      @addFilterFn opt
    return (e)=> @every (fn)-> fn.call(this, e)

  addFilterFn: (opt) ->
    if opt.call?
      return @push opt
    if opt.match?
      @push (e)-> e.match(opt.match)
    if opt.accept?
      @push (e)-> e.accept(opt.accept)
    if opt.reject?
      @push (e)-> not e.reject(opt.reject)

    if not opt.allFiles
      @push (e)-> not e.excluded
    if opt.isFile
      @push (e)-> e.isFile()
    if opt.isDirectory
      @push (e)-> e.isDirectory()

class WalkEntry
  Object.defineProperties @prototype,
    node:
      writable: true
      enumerable: false
    root:
      get: -> @node.root
      enumerable: false

  constructor: (@node) -> @
  init: (@name) -> @
  stat: (cb) ->
    if res = @_stat?
      cb?(@, stat)
    else
      @root.fs_stat @path(), (err, stat) =>
        Object.defineProperty @, '_stat',
          value: stat, enumerable: false
        if err
          console.error 'statError:', err, stat
        cb?(@, stat)
    return @

  path: -> path.resolve @node._path, @name
  isFile: -> @_stat?.isFile()
  isDirectory: -> @_stat?.isDirectory()
  match: (rx, ctx) ->
    if not rx?
      return null
    if rx.call?
      return rx.call(ctx, @)
    return @name.match(rx)?
  exclude: (v) ->
    if v is undefined or !!v
      @excluded = true
    else
      delete @excluded
      return false
  filter: (rx, ctx) ->
    return rx? and @exclude(@match(rx, ctx)) or false
  accept: (rx, ctx) ->
    if not rx? or @match(rx, ctx)
      @exclude(false)
      return true
    else return false
  reject: (rx, ctx) ->
    if not rx? or @match(rx, ctx)
      @exclude(true)
      return true
    else return false

  walk: () ->
    if @excluded or not @isDirectory()
      @root.walk(@path())
      return true
    else return false
  autoWalk: () ->
    if not @excluded and @isDirectory()
      @root.autoWalk(@path(), @root)
      return true
    else return false


class WalkNode
  Object.defineProperties @prototype,
    root:
      writable: true
      enumerable: false
    WalkFuncComp:
      value: WalkFuncComp
  constructor: (@root) ->

  list: (@_path, ee, done) ->
    self = @
    nodeEntry = new @root.WalkEntry @
    @root.fs_readdir @_path, (err, entries) ->
      entries = (entries || []).map (e)->
        Object.create(nodeEntry).init(e)
      self._entries = entries
      ee.emit 'listing', self

      n = entries.length
      entries.forEach (entry) ->
        entry.stat (entry, stat)->
          if stat?
            ee.emit 'entry', entry, self
            if stat.isFile()
              ee.emit 'file', entry, self
            if stat.isDirectory()
              ee.emit 'dir', entry, self
              entry.autoWalk()
          if --n is 0
            ee.emit 'listed', self
            done?(self)
    return self
  
  path: () -> @_path
  base: () -> path.relative(@root._path, @_path)

  entries: () ->
    res = @_entries
    if not res? then return []
    if not arguments.length
      return res
    fn = new @.WalkFuncComp().allEx(arguments)
    return (e for e in res when fn(e))

  filter: (rx, ctx) ->
    @entries (e)-> e.filter(rx,ctx)
  accept: (rx, ctx) ->
    @entries (e)-> e.accept(rx,ctx)
  reject: (rx, ctx) ->
    @entries (e)-> e.reject(rx,ctx)

  matching: (rx, opts...) ->
    if rx?
      opts.unshift {match: rx}
    return @entries opts...
  files: (opts...) ->
    opts.unshift {isFile: true}
    return @entries opts...
  dirs: (opts...) ->
    opts.unshift {isDirectory: true}
    return @entries opts...
  walk: (opts...) ->
    opts.unshift {isDirectory: true}
    for d in @entries opts...
      d.walk()
    return @


createTaskQueue = (nTasks, schedule = process.nextTick) ->
  n = 0
  fnq = []
  _active = false
  step = (c) ->
    if c?
      n -= c
      if not _active
        _active = true
        schedule(step)
    else
      _active = false
      while fnq.length and n<=nTasks
        try n++; fnq.shift()()
        catch err then n--
      queueTask.report?(nTasks, n, fnq.length)
    return nTasks - n - fnq.length

  queueTask = (inner, outer) ->
    fnq.push outer.bind this, ->
      step(1)
      inner.apply(this, arguments)
    return step(0)
  queueTask.clear = ->
    fnq.length = 0
    return step(0)
  queueTask.throttle = (n)->
    nTasks = n
    return step(0)
  return queueTask

class WalkRoot extends events.EventEmitter
  WalkEntry: WalkEntry
  WalkNode: WalkNode
  init: (@_path, opt, schedule=process.nextTick) ->
    events.EventEmitter.call @
    @opt = opt || {}
    @queueTask = createTaskQueue(@opt.tasks || 10, schedule)
    if not @opt.showHidden
      @reject /^\./
    schedule => @walk(@_path)
    return @

  _activeWalks: 0
  walk: (aPath) ->
    aPath = path.resolve(aPath)
    if @_activeWalks++ is 0
      @emit 'active', true
    new @WalkNode(@).list aPath, @, =>
      if --@_activeWalks is 0
        @emit 'active', false

  autoWalk: (aPath, root) ->
    root.walk(aPath)

  filter: (rx, ctx) ->
    if rx?
      @on 'entry', (e)-> e.filter(rx, ctx)
    return @
  accept: (rx, ctx) ->
    if rx?
      @on 'entry', (e)-> e.accept(rx, ctx)
    return @
  reject: (rx, ctx) ->
    if rx?
      @on 'entry', (e)-> e.reject(rx, ctx)
    return @

  fs_stat: (aPath, cb) ->
    @queueTask cb, (cb) ->
      fs.stat aPath, cb

  fs_readdir: (aPath, cb) ->
    @queueTask cb, (cb) ->
      fs.readdir aPath, cb


tromp = (args...) ->
  new tromp.WalkRoot().init(args...)

tromp.WalkFuncComp = WalkFuncComp
tromp.WalkRoot = WalkRoot
tromp.WalkEntry = WalkEntry
tromp.WalkNode = WalkNode
module.exports = tromp.tromp = tromp

