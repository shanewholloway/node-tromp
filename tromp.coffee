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
  Object.defineProperties @.prototype,
    path: get: -> @node.resolve(@name)
    relPath: get: -> @node.relative @path
    rootPath: get: -> @node.rootPath

  constructor: (node) ->
    Object.defineProperty @, 'node', value:node

  create: (name) ->
    Object.create(@, name:{value:name})

  modeKey: ()->
    stat = @stat
    return 'unknown' if not stat?
    return 'file' if stat.isFile()
    return 'dir' if stat.isDirectory()
    return 'other'
  isFile: -> @stat?.isFile()
  isDirectory: -> @stat?.isDirectory()
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
    @node.root.walk(@path, @) if @isWalkable(force)

  toString: -> @path
  toJSON: -> @toString()
  inspect: -> @relPath


class WalkListing
  Object.defineProperties @.prototype,
    path: get:-> @node.resolve()
    relPath: get:-> @node.relative @path
    rootPath: get:-> @node.rootPath

  constructor: (node) ->
    Object.defineProperty @, 'node', value:node

  _performListing: (root, done) ->
    if @_entries is not undefined
      return false
    self = @; @_entries = null
    entry = new @node.WalkEntry(@node)
    root._fs_readdir @path, (err, entries) ->
      if err?
        root.error?('fs.readdir', err, self)
      entries = (entries || []).map (e)->
        entry.create(e)
      self._entries = entries
      root.emit 'listing', self

      n = entries.length
      entries.forEach (entry) ->
        root._fs_stat entry.path, (err, stat) ->
          Object.defineProperty entry, 'stat', {value:stat}
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
    res = {path:@path, relPath:@relPath}
    for e in @select()
      (res[e.modeKey()+'s']||=[]).push e.name
    return res


createTaskQueue = (nTasks=1, schedule = process.nextTick) ->
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
    if not outer?
      outer = inner; inner = null
    fnq.push -> outer ->
      step(1)
      inner?.apply(this, arguments)
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
      root:{value:root}

  create: (listPath, entry) ->
    return Object.create @,
      listPath:{value: listPath}
      rootPath:{value: entry?.rootPath || listPath}
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
    @_node = new @.WalkNode(@)
    @queueTask = createTaskQueue(opt.tasks || 10, opt.schedule)
    if path?
      opt.schedule => @walk(path)
    return @

  walk: (aPath, entry) ->
    if aPath.isWalkable?()
      entry = aPath; aPath = entry.path
    aPath = path.resolve(aPath)
    track = (@_activeWalks ||= [0])
    if aPath not in track
      track[aPath] = node = @_node.create(aPath, entry)
      if track[0] is 0
        @emit 'start'
      @emit 'active', ++track[0], +1, track
      node._performListing =>
        delete track[aPath]
        @emit 'active', --track[0], -1, track
        if track[0] is 0
          @emit('done')

  autoWalk: (entry) -> entry.walk()

  done: (callback)->
    if 0 is @_activeWalks?[0]
      callback()
    else @once('done', callback)

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

