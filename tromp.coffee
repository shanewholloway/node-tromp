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
  Object.defineProperties @prototype,
    root:{get:-> @listing.root}
    path:{get:-> path.resolve(@listing.path, @name)}
    rootPath:{get:-> @listing.rootPath}
    relPath:{get:-> path.relative(@listing.rootPath, @path)}

  constructor: (listing) ->
    Object.defineProperties @,
      listing:{value:listing, enumerable: false}

  init: (name) ->
    res = Object.create(@)
    res.name = name
    return res
  stat: (root, cb) ->
    if res = @_stat?
      cb?(@, stat)
    else
      root._fs_stat @path, (err, stat) =>
        Object.defineProperty @, '_stat',
          value: stat, enumerable: false
        if err
          console.error 'statError:', err, stat
        cb?(@, stat)
    return @

  modeKey: ()->
    stat = @_stat
    return 'unknown' if not stat?
    return 'file' if stat.isFile()
    return 'dir' if stat.isDirectory()
    return 'other'
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

  isWalkable: () ->
    return not @excluded and @isDirectory()
  walk: () ->
    @root.walk(@path, @) if @isWalkable()

  toJSON: -> @path
  toString: -> @path
  valueOf: -> @path
  inspect: -> @path


class WalkListing
  Object.defineProperties @prototype,
    listing:{get:-> @}
    relPath:{get:-> path.relative(@rootPath, @path)}

  constructor: (root, aPath, parent) ->
    Object.defineProperties @,
      root:{value:root, enumerable: false}
      path:{value:aPath}
      rootPath:
        value:parent?.rootPath || aPath
        enumerable: false

  _performListing: (root, done) ->
    if @_entries is not undefined
      return false
    self = @; @_entries = null
    entry = new @root.WalkEntry @
    root._fs_readdir @path, (err, entries) ->
      entries = (entries || []).map (e)->
        entry.init(e)
      self._entries = entries
      root.emit 'listing', self

      n = entries.length
      entries.forEach (entry) ->
        entry.stat root, (entry, stat)->
          if stat?
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
      console.log 'res:', res
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
    res = {path:@path, relPath:@relPath, rootPath:@rootPath}
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


class WalkRoot extends events.EventEmitter
  WalkEntry: WalkEntry
  WalkListing: WalkListing

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
    @queueTask = createTaskQueue(opt.tasks || 10, opt.schedule)
    if path?
      opt.schedule => @walk(path)
    return @

  walk: (aPath, entry) ->
    aPath = path.resolve(aPath)
    track = @_activeWalks
    if aPath not in track
      track[aPath] = listing = new @WalkListing(@, aPath, entry)
      @emit 'active', ++track[0], +1, track
      listing._performListing @, =>
        delete track[aPath]
        @emit 'active', --track[0], -1, track

  autoWalk: (entry) -> entry.walk()

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

  _fs_stat: (aPath, cb) ->
    @queueTask cb, (cb) -> fs.stat aPath, cb
  _fs_readdir: (aPath, cb) ->
    @queueTask cb, (cb) -> fs.readdir aPath, cb


tromp = (path, opt, callback) ->
  new tromp.WalkRoot(path, opt, callback)

tromp.WalkRoot = WalkRoot
tromp.WalkEntry = WalkEntry
tromp.WalkListing = WalkListing
module.exports = tromp.tromp = tromp

