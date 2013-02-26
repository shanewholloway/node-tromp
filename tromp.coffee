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

class WalkEntry
  constructor: (node) ->
    Object.defineProperty @, 'node',
      value:node, enumerable: false

  create: (name) ->
    Object.create(@, name:{value:name})
  stat: (root, done) ->
    if not @_stat?
      root._fs_stat @path(), (err, stat) =>
        Object.defineProperty @, '_stat',
          value: stat, enumerable: false
        done?(err, @, stat)
    else done?(null, @, stat)
    return @

  path: -> @node.resolve(@name)
  relPath: -> @node.relative @path()
  rootPath: -> @node.rootPath

  modeKey: ()->
    stat = @_stat
    return 'unknown' if not stat?
    return 'file' if stat.isFile()
    return 'dir' if stat.isDirectory()
    return 'other'
  isFile: -> @_stat?.isFile()
  isDirectory: -> @_stat?.isDirectory()
  match: (rx, ctx) ->
    return null if not rx?
    return rx.call(ctx, @.name) if rx.call?
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

  isWalkable: (include) ->
    return (include or not @excluded) and @isDirectory()
  walk: (force) ->
    @node.root.walk(@path(), @) if @isWalkable(force)

  toString: -> @path()
  toJSON: -> @toString()
  valueOf: -> @toString()
  inspect: -> @relPath()


class WalkListing
  constructor: (node) ->
    Object.defineProperty @, 'node',
      value:node, enumerable: false

  path: -> @node.resolve()
  relPath: -> @node.relative @path()
  rootPath: -> @node.rootPath

  _performListing: (root, done) ->
    if @_entries is not undefined
      return false
    self = @; @_entries = null
    entry = new @node.WalkEntry(@node)
    root._fs_readdir @path(), (err, entries) ->
      if err?
        root.error?('fs.readdir', err, self)
      entries = (entries || []).map (e)->
        entry.create(e)
      self._entries = entries
      root.emit 'listing', self

      n = entries.length
      entries.forEach (entry) ->
        entry.stat root, (err, entry, stat)->
          if err?
            root.error?('fs.stat', err, entry, self)
          if stat?
            root.emit 'filter', entry, self
            if not entry.excluded
              root.emit 'entry', entry, self
              root.emit entry.modeKey(), entry, self
              if entry.isWalkable()
                root.autoWalk(entry)
          if --n is 0
            root.emit 'listed', self
            done?(self)
    return self
  
  selectEx: (fnList) ->
    res = (@_entries or [])
    if fnList?
      res = res.filter (entry) ->
        fnList.every((fn)->fn(entry))
    return res
  select: (fnList=[]) ->
    fnList.unshift (e)-> not e.excluded
    return @selectEx(fnList)

  matching: (rx, opts...) ->
    opts.unshift (e)-> e.match(rx)
    return @select opts...
  files: (opts...) ->
    opts.unshift (e)->e.isFile()
    return @select opts...
  dirs: (opts...) ->
    opts.unshift (e)->e.isDirectory()
    return @select opts...
  walk: (opts...) ->
    opts.unshift (e)->e.isDirectory()
    for d in @select opts...
      d.walk()
    return @
  filter: (rx, ctx) ->
    @selectEx (e)-> e.filter(rx,ctx)
  accept: (rx, ctx) ->
    @selectEx (e)-> e.accept(rx,ctx)
  reject: (rx, ctx) ->
    @selectEx (e)-> e.reject(rx,ctx)

  inspect: -> @toJSON()
  toJSON: ->
    res = {path:@path(), relPath:@relPath()}
    for e in @select()
      (res[e.modeKey()+'s']||=[]).push e.name
    return res


createTaskQueue = (nTasks, schedule = process.nextTick) ->
  n = 0; fnq = []; _active = false
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


class WalkNode
  WalkListing: WalkListing
  WalkEntry: WalkEntry

  constructor: (root) ->
    Object.defineProperties @,
      root:{value:root, enumerable: false}

  create: (listPath, entry) ->
    return Object.create @,
      listPath:{value: listPath}
      rootPath:{value: entry?.rootPath() || listPath}
      entry:{value: entry}

  _performListing: (done) ->
    new @.WalkListing(@)._performListing(@root, done)

  resolve: (args...)-> path.resolve(@listPath, args...)
  relative: (args...)-> path.relative(@rootPath, args...)


class WalkRoot extends events.EventEmitter
  WalkNode: WalkNode
  constructor: (path, opt, callback) ->
    events.EventEmitter.call @
    if 'function' is typeof opt
      callback = opt; opt = {}
    else opt ||= {}
    @on('listed', callback) if callback?
    if not opt.showHidden
      @reject /^\./
    if opt.autoWalk?
      @autoWalk = opt.autoWalk or (-> null)

    opt.schedule ||= process.nextTick
    @_activeWalks = [0]
    @_node = new @.WalkNode(@)
    @queueTask = createTaskQueue(opt.tasks || 10, opt.schedule)
    if path?
      opt.schedule => @walk(path)
    return @

  walk: (aPath, entry) ->
    if aPath.isWalkable?()
      entry = aPath; aPath = entry.path()
    aPath = path.resolve(aPath)
    track = @_activeWalks
    if aPath not in track
      track[aPath] = node = @_node.create(aPath, entry)
      if track[0] is 0
        @emit 'start'
      @emit 'active', ++track[0], +1, track
      node._performListing =>
        delete track[aPath]
        @emit 'active', --track[0], -1, track
        if track[0] is 0
          @emit 'done'

  autoWalk: (entry) -> entry.walk()

  filter: (rx, ctx) ->
    if rx?
      @on 'filter', (e)-> e.filter(rx, ctx)
    return @
  accept: (rx, ctx) ->
    if rx?
      @on 'filter', (e)-> e.accept(rx, ctx)
    return @
  reject: (rx, ctx) ->
    if rx?
      @on 'filter', (e)-> e.reject(rx, ctx)
    return @

  _fs_stat: (aPath, cb) ->
    @queueTask cb, (cb) -> fs.stat aPath, cb
  _fs_readdir: (aPath, cb) ->
    @queueTask cb, (cb) -> fs.readdir aPath, cb

tromp = (path, opt, callback) ->
  new tromp.WalkRoot(path, opt, callback)

tromp.WalkRoot = WalkRoot
tromp.WalkNode = WalkNode
tromp.WalkEntry = WalkEntry
tromp.WalkListing = WalkListing
module.exports = tromp.tromp = tromp

