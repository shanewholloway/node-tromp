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
{closureQueue, taskQueue} = require './funcQueues'

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

  constructor: (node, name)->
    Object.defineProperty @, 'node', value:node
    if name?
      Object.defineProperty @, 'name', value:name

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
      @node.root.autoWalk?(@, target)
  walk: (target, opt={})->
    if @isWalkable(opt.force)
      root = opt.root || @node.root
      return root.walk(@, target||@node.target)
  walkPath: -> @path

  toString: -> @path
  toJSON: -> @toString()
  inspect: -> @relPath


class WalkListing extends events.EventEmitter
  Object.defineProperties @.prototype,
    path: get:-> @node.resolve()
    relPath: get:-> @node.relative @path
    rootPath: get:-> @node.rootPath

  constructor: (node)->
    super()
    Object.defineProperty @, 'node', value:node

  _performListing: (target, done)->
    if @_entries is not undefined
      return false
    @_entries = null
    listing = @; node = @node
    entry0 = node.newEntry()

    if target?
      targetFn = (target.walkNotify || target.emit || target).bind(target)
      notify = => @emit(arguments...); targetFn(arguments...)
    else notify = @emit.bind(@)

    notify 'listing_pre', listing
    postDone = (err)->
      notify 'listed', listing
      done?(err, listing, target)
      return

    node._fs_readdir @path, (err, entries)->
      if err?
        notify 'error', err, {op:'fs.readdir', listing:listing}

      entries = (entries||[]).map (e)-> entry0.create(e)
      listing._entries = entries

      notify 'listing', listing
      n = entries.length
      if n is 0
        postDone()
        return

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
            postDone()
          return
      return
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


class WalkNode
  WalkEntry: WalkEntry
  WalkListing: WalkListing
  constructor: (root, opt, doneFn)->
    Object.defineProperties @,
      root: value: root
      fs: value: opt?.fs || @fs
      walkQueue: value: closureQueue(doneFn)
      _fs_queue: value: taskQueue(tasks:opt.tasks || 10)

  create: (listPath, entry, target)->
    listPath = path.resolve(listPath)
    return Object.create @,
      listPath:{value: listPath}
      rootPath:{value: entry?.rootPath || listPath}
      entry:{value: entry}
      target:{value: target}

  newEntry: (name)-> new @.WalkEntry(@, name)
  newEntryForPath: (aPath, target)->
    self = @create(path.dirname(aPath), null, target)
    return self.newEntry(path.basename(aPath))

  newListing: (pathOrEntry, target)->
    if pathOrEntry.isWalkable?() # is it an entry?
      self = @create(pathOrEntry.walkPath?() or pathOrEntry.path, pathOrEntry, target)
    else # must be a path
      self = @create(pathOrEntry, null, target)
    return new @.WalkListing(self)
  walk: (pathOrEntry, target)->
    listing = @newListing(pathOrEntry, target)
    listing._performListing(target, @walkQueue())
    return listing

  resolve: (args...)-> path.resolve(@listPath, args...)
  relative: (args...)-> path.relative(@rootPath, args...)

  addEntryFilter: (fns...)->
    @entryFilters = (@entryFilters||[]).concat(fns)
  filterEntry: (entry)->
    if @entryFilters?
      for fn in @entryFilters
        try fn(entry) catch err

  fs: fs
  _fs_stat: (aPath, callback)->
    fs = @fs; @_fs_queue (task)->
      fs.stat(aPath, task.wrap(callback))

  _fs_readdir: (aPath, callback)->
    fs = @fs; @_fs_queue (task)->
      fs.readdir(aPath, task.wrap(callback))


class WalkRoot extends events.EventEmitter
  WalkNode: WalkNode
  constructor: (opt={})->
    super()
    @node = new @.WalkNode(@, opt, =>@emit('done'))

    @reject(/^\./) if not opt.showHidden
    if opt.autoWalk?
      @autoWalk = opt.autoWalk or (-> null)

  walk: (pathOrEntry, target=@)->
    @node.walk(pathOrEntry, target||@)
  autoWalk: (entry, target)->
    entry.walk(target)

  #walkNotify: (eventKey, args...)->
  walkNotify: events.EventEmitter::emit

  isDone: ()-> return @node.walkQueue.isDone()
  done: (callback)->
    if not @isDone()
      @on('done', callback)
    else callback()
    return @
  filter: (args...)->
    if args[0]?
      @node.addEntryFilter (e)-> e.filter(args...)
    return @
  accept: (args...)->
    if args[0]?
      @node.addEntryFilter (e)-> e.accept(args...)
    return @
  reject: (args...)->
    if args[0]?
      @node.addEntryFilter (e)-> e.reject(args...)
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

