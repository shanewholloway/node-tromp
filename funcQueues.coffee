# -*- coding: utf-8 -*- vim: set ts=2 sw=2 expandtab
##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
##~ Copyright (C) 2002-2013  TechGame Networks, LLC.              ##
##~                                                               ##
##~ This library is free software; you can redistribute it        ##
##~ and/or modify it under the terms of the MIT style License as  ##
##~ found in the LICENSE file included with this distribution.    ##
##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##


# `functionList()` creates a new function list with an `invoke()` method that
# will call each function in the list with the supplied arguments. Also
# provides function-like methods of `bind()`, `call()` and `apply()` to provide
# a callable API.

functionList = do ->
  invokeEach = (self, args, error)->
    for fn in self
      try fn(args...)
      catch err
        if self.error? then self.error(err)
        else if error? then error(err)
        else console.error(err.stack or err)

  methods =
    bind: (args...)-> @invoke.bind(args...)
    call: (args...)-> @invoke.call(args...)
    apply: (self, args)-> @invoke.apply(self, args)

  init = (self, args...)->
    desc = {}
    for each of args
      for own k,v of each
        desc[k] = value:v
    Object.defineProperties(self, desc)
    return self


  create = (self=[], error)->
    init self, methods,
      once: []
      invoke: ->
        invokeEach(self.once.splice(0), arguments, error)
        invokeEach(self, arguments, error)
        return @
  create.create = create

  create.list = (self=[], error)->
    init self, methods,
      invoke: -> invokeEach(self, arguments, error); return @

  create.once = (self=[], error)->
    init self, methods,
      invoke: -> invokeEach(self.splice(0), arguments, error); return @

  return create
exports.functionList = functionList
exports.funcList = funcList = functionList
exports.fnList = fnList = functionList


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# `closureQueue()` tracks the number of started and completed closures.
# Great for knowing when things are done.

closureQueue = (tgt, callback)->
  if typeof tgt is 'function'
    callback = tgt; tgt=null

  n0 = 0; n1 = 0
  start = (callback)->
    self.start?(self, n1 - n0++)
    return finish if not callback?
    return finish.wrap(callback)
  finish = ->
    isdone = ++n1 is n0
    self.finish?(self, n1-n0)
    if isdone?
      self.done?.call(self, self, n1)
      callback?(null, self, n1)
    return isdone
  finish.wrap = (callback)->
    return finish if not callback?
    return ->
      try callback.apply(@, arguments)
      finally finish()
  
  Object.defineProperties self=start,
    started: get:-> n0
    completed: get:-> n1
    active: get:-> n1-n0
    valueOf: value:-> n1-n0
    isIdle: value:-> n1 is n0
    isDone: value:-> n1 is n0 and n0>0
  if tgt?
    self[k]=v for k,v of tgt
  return self
exports.closureQueue = closureQueue


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# `taskQueue()` manages a collection of task functions combined with a
# `closureQueue()` to track (and throttle) parallel active tasks.

taskQueue = (limit, tgt, callback)->
  if typeof limit is 'function'
    callback = limit; tgt=null; limit = 9e9
  if typeof tgt is 'function'
    callback = tgt; tgt=null
  if not (typeof limit is 'number')
    tgt = limit; limit = (tgt.limit||9e9)+0

  cq = closureQueue
    finish: (cq, nActive)->
      self.step(-1); return
    done: (cq, nComplete)->
      callback?(null, self, n0)
      self.done?.call(self, self, n0); return

  taskq = []
  addTask = (fn)->
    taskq.push(fn); self.step(+1); self
  step = ->
    while taskq.length>0 and limit>=cq.active
      if self.invokeTask(taskq.shift(), cq)
        return self
    return self
  invokeTask = (task, cq)->
    try task?(cq())
    catch err
      if self.error? then self.error(err)
      else console.error(err.stack or err)
    return

  Object.defineProperties self=addTask,
    active: get:-> cq.active
    backlog: get:-> taskq.length
    incomplete: get:-> cq.active+taskq.length
    completed: get:-> cq.completed
    step: value: step
    invokeTask: value: invokeTask
    isIdle: value:-> taskq.length is 0 and cq.isIdle()
    isDone: value:-> taskq.length is 0 and cq.isDone()
  if tgt?
    self[k]=v for k,v of tgt
  return self
exports.taskQueue = taskQueue


