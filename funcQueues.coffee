# -*- coding: utf-8 -*- vim: set ts=2 sw=2 expandtab
##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
##~ Copyright (C) 2002-2013  TechGame Networks, LLC.              ##
##~                                                               ##
##~ This library is free software; you can redistribute it        ##
##~ and/or modify it under the terms of the MIT style License as  ##
##~ found in the LICENSE file included with this distribution.    ##
##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##

closureQueue = (tgt, callback)->
  if typeof tgt is 'function'
    callback = tgt; tgt=null

  n0 = 0; n1 = 0
  start = ->
    self.start?(self, n1-n0)
    ++n0; return finish
  finish = ->
    isdone = ++n1 is n0
    self.finish?(self, n1-n0)
    if isdone?
      self.done?(self, n1)
      callback?(null, self, n1)
    return isdone
  finish.wrap = (callback)->
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
    tgt[k]=v for k,v of tgt
  return self

exports.closureQueue = closureQueue

taskQueue = (limit, tgt, callback)->
  if typeof limit is 'function'
    callback = limit; tgt=null; limit = 9e9
  if typeof tgt is 'function'
    callback = tgt; tgt=null
  if not (typeof limit is 'number')
    tgt = limit; limit = (tgt.limit||9e9)+0

  cq = closureQueue
    finish: (cq, nActive)-> step(); return
    done: (cq, nComplete)->
      callback?(null, self, n0)
      self.done?(self, n0); return

  taskq = []
  addTask = (fn)-> taskq.push(fn); step(); self
  step = ->
    while taskq.length>0 and limit>=cq.active
      task = taskq.shift()
      try task?(cq())
      catch err
        if self.error? then self.error(err)
        else console.error(err.stack or err)
    return self

  Object.defineProperties self=addTask,
    active: get:-> cq.active
    backlog: get:-> taskq.length
    incomplete: get:-> cq.active+taskq.length
    completed: get:-> cq.completed
    isIdle: value:-> taskq.length is 0 and cq.isIdle()
    isDone: value:-> taskq.length is 0 and cq.isDone()
  if tgt?
    tgt[k]=v for k,v of tgt
  return self

exports.taskQueue = taskQueue
