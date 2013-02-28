# -*- coding: utf-8 -*- vim: set ts=2 sw=2 expandtab
##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
##~ Copyright (C) 2002-2013  TechGame Networks, LLC.              ##
##~                                                               ##
##~ This library is free software; you can redistribute it        ##
##~ and/or modify it under the terms of the MIT style License as  ##
##~ found in the LICENSE file included with this distribution.    ##
##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##

fs = require 'fs'
path = require 'path'
events = require 'events'

modeForStat = (stat) ->
  return 'unknown' if not stat?
  return 'file' if stat.isFile()
  return 'dir' if stat.isDirectory()
  return 'symlink' if stat.isSymbolicLink()
  return 'other'

class WalkEntry
  Object.defineProperties @.prototype,
    path: get: -> @node.resolve(@name)
    relPath: get: -> @node.relative @path
    rootPath: get: -> @node.rootPath
    modeKey: get: -> @mode

  constructor: (node)->
    Object.defineProperty @, 'node', value:node

  create: (name)->
    Object.create(@, name:{value:name})

  mode: modeForStat(null)
  initStat: (stat)->
    Object.defineProperties @,
      stat: value:stat
      mode: value:modeForStat(stat)
    return @
  isFile: -> @stat?.isFile()
  isDirectory: -> @stat?.isDirectory()
  match: (rx, ctx)->
    return null if not rx?
    return rx.call(ctx, @.name) if rx.call?
    return @name.match(rx)?
  exclude: (v)->
    if v is undefined or !!v
      @excluded = true
    else
      delete @excluded
      return false
  filter: (rx, ctx)->
    return rx? and @exclude(@match(rx, ctx)) or false
  accept: (rx, ctx)->
    if not rx? or @match(rx, ctx)
      @exclude(false)
      return true
    else return false
  reject: (rx, ctx)->
    if not rx? or @match(rx, ctx)
      @exclude(true)
      return true
    else return false

  isWalkable: (include)->
    return (include or not @excluded) and @isDirectory()

  autoWalk: (target)->
    if @isWalkable()
      @node.root.autoWalk(@, target)
  walk: (target, opt={})->
    if @isWalkable(opt.force)
      root = opt.root || @node.root
      return root.walk(@, target||@node.target)

  toString: -> @path
  toJSON: -> @toString()
  inspect: -> @relPath


class WalkListing
  Object.defineProperties @.prototype,
    path: get:-> @node.resolve()
    relPath: get:-> @node.relative @path
    rootPath: get:-> @node.rootPath

  constructor: (node)->
    Object.defineProperty @, 'node', value:node

  _performListing: (target, done)->
    if @_entries is not undefined
      return false
    @_entries = null
    listing = @; node = @node
    entry0 = node.newEntry()

    if not (typeof target is 'function')
      notify = (target.walkNotify || target.emit || ->).bind(target)
    else notify = target

    notify 'listing_pre', listing
    node._fs_readdir @path, (err, entries)->
      if err?
        notify 'error', err, {op:'fs.readdir', listing:listing}

      entries = (entries||[]).map (e)-> entry0.create(e)
      listing._entries = entries

      notify 'listing', listing
      n = entries.length
      entries.forEach (entry)->
        node._fs_stat entry.path, (err, stat)->
          if err?
            notify 'error', err, {op:'fs.stat', entry:entry, listing:listing}
          if stat?
            entry.initStat(stat)
            node.filterEntry(entry)
            notify 'filter', entry, listing
            if not entry.excluded
              notify 'entry', entry, listing
              notify entry.mode, entry, listing
              entry.autoWalk(target)
          if --n is 0
            notify 'listed', listing
            done?(listing, target)
    return @
  
  selectEx: (fnList)->
    res = (@_entries or [])
    if fnList?
      res = res.filter (entry)->
        fnList.every((fn)->fn(entry))
    return res
  select: (fnList=[])->
    fnList.unshift (e)-> not e.excluded
    return @selectEx(fnList)

  matching: (rx, opts...)->
    opts.unshift (e)-> e.match(rx)
    return @select(opts...)
  files: (opts...)->
    opts.unshift (e)->e.isFile()
    return @select(opts...)
  dirs: (opts...)->
    opts.unshift (e)->e.isDirectory()
    return @select(opts...)
  filter: (rx, ctx)->
    @selectEx (e)-> e.filter(rx,ctx)
  accept: (rx, ctx)->
    @selectEx (e)-> e.accept(rx,ctx)
  reject: (rx, ctx)->
    @selectEx (e)-> e.reject(rx,ctx)

  inspect: -> @toJSON()
  toJSON: ->
    res = {path:@path, relPath:@relPath}
    for e in @select()
      (res[e.mode+'s']||=[]).push e.name
    return res


createTaskQueue = (opt={})->
  nextTick = opt.schedule || process.nextTick
  nMaxTasks = opt.tasks || 9e9
  nComplete = 0; nActive = 0
  taskq = []; live = false

  self = queueTask = (outer, inner)->
    if inner?
      inner_finish =-> finish(); inner(arguments...)
    else inner_finish = finish
    taskq.push(-> outer(inner_finish))
    return schedule()

  Object.defineProperties self,
    active: get:-> nActive
    total: get:-> nActive+taskq.length
    incomplete: get:-> taskq.length
    complete: get:-> nComplete

  finish = ->
    ++nComplete; --nActive; schedule(); return
  schedule = ->
    nextTick(runTasks) if not live++
    return self
  runTasks = ->
    live = false
    while taskq.length and nActive<=nMaxTasks
      try nActive++; taskq.shift()()
      catch err
        nActive--; self.error(err)
    updateFns.invoke(self, nActive, taskq.length)
    idleFns.invoke(self) if isIdle()
    return

  self.isIdle = isIdle = (min)->
    (0 is nActive) and (0 is taskq.length) and (not min? or min<=nComplete)
  self.throttle = (n)-> nMaxTasks = n; return schedule()
  self.error = opt.error || (err)-> console.error(err.stack)

  invokeEach = ->
    for fn in this
      try fn(arguments...)
      catch err
        self.error(err)

  (updateFns=[]).invoke = invokeEach
  self.update = (callback)->
    updateFns.push callback
    return

  (idleFns=[]).invoke = invokeEach
  self.idle = (callback)->
    idleFns.push callback
    if isIdle()
      callback(self)
  return self


class WalkNode
  WalkEntry: WalkEntry
  WalkListing: WalkListing
  constructor: (root, opt)->
    Object.defineProperties @,
      root:{value:root},
      walkQueue: value: createTaskQueue()
      _fs_queue:
        value: createTaskQueue(tasks:opt.tasks || 10)

  create: (listPath, entry, target)->
    listPath = path.resolve(listPath)
    return Object.create @,
      listPath:{value: listPath}
      rootPath:{value: entry?.rootPath || listPath}
      entry:{value: entry}
      target:{value: target}

  newEntry: -> new @.WalkEntry(@)
  newListing: (pathOrEntry, target)->
    if pathOrEntry.isWalkable?() # is it an entry?
      self = @create(pathOrEntry.path, pathOrEntry, target)
    else # must be a path
      self = @create(pathOrEntry, null, target)
    return new @.WalkListing(self)
  walk: (pathOrEntry, target)->
    listing = @newListing(pathOrEntry, target)
    @walkQueue (done)->
      listing._performListing(target, done)
    return listing

  resolve: (args...)-> path.resolve(@listPath, args...)
  relative: (args...)-> path.relative(@rootPath, args...)

  addEntryFilter: (fns...)->
    @entryFilters = (@entryFilters||[]).concat(fns)
  filterEntry: (entry)->
    if @entryFilters?
      for fn in @entryFilters
        try fn(entry) catch err

  _fs_stat: (aPath, callback)->
    @_fs_queue(
      (next)-> fs.stat(aPath, next)
      callback)
  _fs_readdir: (aPath, callback)->
    @_fs_queue(
      (next)-> fs.readdir(aPath, next)
      callback)


class WalkRoot extends events.EventEmitter
  WalkNode: WalkNode
  constructor: (opt={})->
    events.EventEmitter.call @
    @node = new @.WalkNode(@, opt)
    @node.walkQueue.idle (q)=>
      @emit('done') if q.complete>0

    @reject(/^\./) if not opt.showHidden
    if opt.autoWalk?
      @autoWalk = opt.autoWalk or (-> null)

  walk: (pathOrEntry, target=@)->
    @node.walk(pathOrEntry, target||@)
  autoWalk: (entry, target)->
    entry.walk(target)

  isDone: ()->
    return @node.walkQueue.isIdle(1)
  done: (callback)->
    if not @isDone()
      @on('done', callback)
    else callback()
    return @
  filter: (args...)->
    @node.addEntryFilter (e)-> e.filter(args...) if args[0]?
    return @
  accept: (args...)->
    @node.addEntryFilter (e)-> e.accept(args...) if args[0]?
    return @
  reject: (args...)->
    @node.addEntryFilter (e)-> e.reject(args...) if args[0]?
    return @

tromp = (path, opt, callback)->
  if typeof opt is 'function'
    callback = opt; opt = null
  if typeof path is not 'string'
    opt = path; path = null
  root = new tromp.WalkRoot(opt)
  root.on('listing', callback) if callback?
  path ||= opt?.path
  root.walk(path) if path?
  return root

tromp.WalkRoot = WalkRoot
tromp.WalkNode = WalkNode
tromp.WalkEntry = WalkEntry
tromp.WalkListing = WalkListing
module.exports = tromp.tromp = tromp

