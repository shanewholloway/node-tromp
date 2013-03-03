// Generated by CoffeeScript 1.4.0
var closureQueue, fnList, funcList, functionList, taskQueue,
  __slice = [].slice,
  __hasProp = {}.hasOwnProperty;

functionList = (function() {
  var create, init, invokeEach, methods;
  invokeEach = function(self, args, error) {
    var fn, _i, _len, _results;
    _results = [];
    for (_i = 0, _len = self.length; _i < _len; _i++) {
      fn = self[_i];
      try {
        _results.push(fn.apply(null, args));
      } catch (err) {
        if (self.error != null) {
          _results.push(self.error(err));
        } else if (error != null) {
          _results.push(error(err));
        } else {
          _results.push(console.error(err.stack || err));
        }
      }
    }
    return _results;
  };
  methods = {
    bind: function() {
      var args, _ref;
      args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
      return (_ref = this.invoke).bind.apply(_ref, args);
    },
    call: function() {
      var args, _ref;
      args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
      return (_ref = this.invoke).call.apply(_ref, args);
    },
    apply: function(self, args) {
      return this.invoke.apply(self, args);
    }
  };
  init = function() {
    var args, desc, each, k, self, v;
    self = arguments[0], args = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
    desc = {};
    for (each in args) {
      for (k in each) {
        if (!__hasProp.call(each, k)) continue;
        v = each[k];
        desc[k] = {
          value: v
        };
      }
    }
    Object.defineProperties(self, desc);
    return self;
  };
  create = function(self, error) {
    if (self == null) {
      self = [];
    }
    return init(self, methods, {
      once: [],
      invoke: function() {
        invokeEach(self.once.splice(0), arguments, error);
        invokeEach(self, arguments, error);
        return this;
      }
    });
  };
  create.create = create;
  create.list = function(self, error) {
    if (self == null) {
      self = [];
    }
    return init(self, methods, {
      invoke: function() {
        invokeEach(self, arguments, error);
        return this;
      }
    });
  };
  create.once = function(self, error) {
    if (self == null) {
      self = [];
    }
    return init(self, methods, {
      invoke: function() {
        invokeEach(self.splice(0), arguments, error);
        return this;
      }
    });
  };
  return create;
})();

exports.functionList = functionList;

exports.funcList = funcList = functionList;

exports.fnList = fnList = functionList;

closureQueue = function(tgt, callback) {
  var finish, k, nComplete, nStarted, self, start, v;
  if (typeof tgt === 'function') {
    callback = tgt;
    tgt = null;
  }
  nStarted = 0;
  nComplete = 0;
  start = function(callback) {
    if (typeof self.start === "function") {
      self.start(self, nComplete - nStarted);
    }
    nStarted++;
    if (!(callback != null)) {
      return finish;
    }
    return finish.wrap(callback);
  };
  finish = function() {
    var isdone, _ref;
    isdone = ++nComplete === nStarted;
    if (typeof self.finish === "function") {
      self.finish(self, nComplete - nStarted);
    }
    if (isdone != null) {
      if ((_ref = self.done) != null) {
        _ref.call(self, self, nComplete);
      }
      if (typeof callback === "function") {
        callback(null, self, nComplete);
      }
    }
    return isdone;
  };
  finish.wrap = function(callback) {
    if (!(callback != null)) {
      return finish;
    }
    return function() {
      try {
        return callback.apply(this, arguments);
      } finally {
        finish();
      }
    };
  };
  Object.defineProperties(self = start, {
    started: {
      get: function() {
        return nStarted;
      }
    },
    completed: {
      get: function() {
        return nComplete;
      }
    },
    active: {
      get: function() {
        return nComplete - nStarted;
      }
    },
    inspect: {
      value: function() {
        return "[closureQueue active: " + this.active + " completed: " + this.completed + "]";
      }
    },
    toString: {
      value: function() {
        return this.inspect();
      }
    },
    isIdle: {
      value: function() {
        return nComplete === nStarted;
      }
    },
    isDone: {
      value: function() {
        return nComplete === nStarted && nStarted > 0;
      }
    }
  });
  if (tgt != null) {
    for (k in tgt) {
      v = tgt[k];
      self[k] = v;
    }
  }
  return self;
};

exports.closureQueue = closureQueue;

taskQueue = function(limit, tgt, callback) {
  var addTask, cq, invokeTask, k, self, step, taskq, v;
  if (typeof limit === 'function') {
    callback = limit;
    tgt = null;
    limit = 9e9;
  }
  if (typeof tgt === 'function') {
    callback = tgt;
    tgt = null;
  }
  if (!(typeof limit === 'number')) {
    tgt = limit;
    limit = (tgt.limit || 9e9) + 0;
  }
  cq = closureQueue({
    finish: function(cq, nActive) {
      self.step(-1);
    },
    done: function(cq, nComplete) {
      var _ref;
      if (typeof callback === "function") {
        callback(null, self, nComplete);
      }
      if ((_ref = self.done) != null) {
        _ref.call(self, self, nComplete);
      }
    }
  });
  taskq = [];
  addTask = function(fn) {
    taskq.push(fn);
    self.step(+1);
    return self;
  };
  step = function() {
    while (taskq.length > 0 && limit >= cq.active) {
      if (self.invokeTask(taskq.shift(), cq)) {
        return self;
      }
    }
    return self;
  };
  invokeTask = function(task, cq) {
    try {
      if (typeof task === "function") {
        task(cq());
      }
    } catch (err) {
      if (self.error != null) {
        self.error(err);
      } else {
        console.error(err.stack || err);
      }
    }
  };
  Object.defineProperties(self = addTask, {
    active: {
      get: function() {
        return cq.active;
      }
    },
    backlog: {
      get: function() {
        return taskq.length;
      }
    },
    incomplete: {
      get: function() {
        return cq.active + taskq.length;
      }
    },
    completed: {
      get: function() {
        return cq.completed;
      }
    },
    inspect: {
      value: function() {
        return "[taskQueue backlog: " + this.backlog + " active: " + this.active + " completed: " + this.completed + "]";
      }
    },
    toString: {
      value: function() {
        return this.inspect();
      }
    },
    step: {
      value: step
    },
    invokeTask: {
      value: invokeTask
    },
    isIdle: {
      value: function() {
        return taskq.length === 0 && cq.isIdle();
      }
    },
    isDone: {
      value: function() {
        return taskq.length === 0 && cq.isDone();
      }
    }
  });
  if (tgt != null) {
    for (k in tgt) {
      v = tgt[k];
      self[k] = v;
    }
  }
  return self;
};

exports.taskQueue = taskQueue;
