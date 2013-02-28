// Generated by CoffeeScript 1.4.0
var WalkEntry, WalkListing, WalkNode, WalkRoot, createTaskQueue, events, fs, modeForStat, path, tromp,
  __slice = [].slice,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

fs = require('fs');

path = require('path');

events = require('events');

modeForStat = function(stat) {
  if (!(stat != null)) {
    return 'unknown';
  }
  if (stat.isFile()) {
    return 'file';
  }
  if (stat.isDirectory()) {
    return 'dir';
  }
  if (stat.isSymbolicLink()) {
    return 'symlink';
  }
  return 'other';
};

WalkEntry = (function() {

  Object.defineProperties(WalkEntry.prototype, {
    path: {
      get: function() {
        return this.node.resolve(this.name);
      }
    },
    relPath: {
      get: function() {
        return this.node.relative(this.path);
      }
    },
    rootPath: {
      get: function() {
        return this.node.rootPath;
      }
    },
    modeKey: {
      get: function() {
        return this.mode;
      }
    }
  });

  function WalkEntry(node) {
    Object.defineProperty(this, 'node', {
      value: node
    });
  }

  WalkEntry.prototype.create = function(name) {
    return Object.create(this, {
      name: {
        value: name
      }
    });
  };

  WalkEntry.prototype.mode = modeForStat(null);

  WalkEntry.prototype.initStat = function(stat) {
    Object.defineProperties(this, {
      stat: {
        value: stat
      },
      mode: {
        value: modeForStat(stat)
      }
    });
    return this;
  };

  WalkEntry.prototype.isFile = function() {
    var _ref;
    return (_ref = this.stat) != null ? _ref.isFile() : void 0;
  };

  WalkEntry.prototype.isDirectory = function() {
    var _ref;
    return (_ref = this.stat) != null ? _ref.isDirectory() : void 0;
  };

  WalkEntry.prototype.match = function(rx, ctx) {
    if (!(rx != null)) {
      return null;
    }
    if (rx.call != null) {
      return rx.call(ctx, this.name);
    }
    return this.name.match(rx) != null;
  };

  WalkEntry.prototype.exclude = function(v) {
    if (v === void 0 || !!v) {
      return this.excluded = true;
    } else {
      delete this.excluded;
      return false;
    }
  };

  WalkEntry.prototype.filter = function(rx, ctx) {
    return (rx != null) && this.exclude(this.match(rx, ctx)) || false;
  };

  WalkEntry.prototype.accept = function(rx, ctx) {
    if (!(rx != null) || this.match(rx, ctx)) {
      this.exclude(false);
      return true;
    } else {
      return false;
    }
  };

  WalkEntry.prototype.reject = function(rx, ctx) {
    if (!(rx != null) || this.match(rx, ctx)) {
      this.exclude(true);
      return true;
    } else {
      return false;
    }
  };

  WalkEntry.prototype.isWalkable = function(include) {
    return (include || !this.excluded) && this.isDirectory();
  };

  WalkEntry.prototype.autoWalk = function(target) {
    if (this.isWalkable()) {
      return this.node.root.autoWalk(this, target);
    }
  };

  WalkEntry.prototype.walk = function(target, opt) {
    var root;
    if (opt == null) {
      opt = {};
    }
    if (this.isWalkable(opt.force)) {
      root = opt.root || this.node.root;
      return root.walk(this, target || this.node.target);
    }
  };

  WalkEntry.prototype.walkPath = function() {
    return this.path;
  };

  WalkEntry.prototype.toString = function() {
    return this.path;
  };

  WalkEntry.prototype.toJSON = function() {
    return this.toString();
  };

  WalkEntry.prototype.inspect = function() {
    return this.relPath;
  };

  return WalkEntry;

})();

WalkListing = (function() {

  Object.defineProperties(WalkListing.prototype, {
    path: {
      get: function() {
        return this.node.resolve();
      }
    },
    relPath: {
      get: function() {
        return this.node.relative(this.path);
      }
    },
    rootPath: {
      get: function() {
        return this.node.rootPath;
      }
    }
  });

  function WalkListing(node) {
    Object.defineProperty(this, 'node', {
      value: node
    });
  }

  WalkListing.prototype._performListing = function(target, done) {
    var entry0, listing, node, notify;
    if (this._entries === !void 0) {
      return false;
    }
    this._entries = null;
    listing = this;
    node = this.node;
    entry0 = node.newEntry();
    if (!(typeof target === 'function')) {
      notify = (target.walkNotify || target.emit || function() {}).bind(target);
    } else {
      notify = target;
    }
    notify('listing_pre', listing);
    node._fs_readdir(this.path, function(err, entries) {
      var n;
      if (err != null) {
        notify('error', err, {
          op: 'fs.readdir',
          listing: listing
        });
      }
      entries = (entries || []).map(function(e) {
        return entry0.create(e);
      });
      listing._entries = entries;
      notify('listing', listing);
      n = entries.length;
      return entries.forEach(function(entry) {
        return node._fs_stat(entry.path, function(err, stat) {
          if (err != null) {
            notify('error', err, {
              op: 'fs.stat',
              entry: entry,
              listing: listing
            });
          }
          if (stat != null) {
            entry.initStat(stat);
            node.filterEntry(entry);
            notify('filter', entry, listing);
            if (!entry.excluded) {
              notify('entry', entry, listing);
              notify(entry.mode, entry, listing);
              entry.autoWalk(target);
            }
          }
          if (--n === 0) {
            notify('listed', listing);
            return typeof done === "function" ? done(listing, target) : void 0;
          }
        });
      });
    });
    return this;
  };

  WalkListing.prototype.selectEx = function(fnList) {
    var res;
    res = this._entries || [];
    if (fnList != null) {
      res = res.filter(function(entry) {
        return fnList.every(function(fn) {
          return fn(entry);
        });
      });
    }
    return res;
  };

  WalkListing.prototype.select = function(fnList) {
    if (fnList == null) {
      fnList = [];
    }
    fnList.unshift(function(e) {
      return !e.excluded;
    });
    return this.selectEx(fnList);
  };

  WalkListing.prototype.matching = function() {
    var opts, rx;
    rx = arguments[0], opts = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
    opts.unshift(function(e) {
      return e.match(rx);
    });
    return this.select.apply(this, opts);
  };

  WalkListing.prototype.files = function() {
    var opts;
    opts = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    opts.unshift(function(e) {
      return e.isFile();
    });
    return this.select.apply(this, opts);
  };

  WalkListing.prototype.dirs = function() {
    var opts;
    opts = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    opts.unshift(function(e) {
      return e.isDirectory();
    });
    return this.select.apply(this, opts);
  };

  WalkListing.prototype.filter = function(rx, ctx) {
    return this.selectEx(function(e) {
      return e.filter(rx, ctx);
    });
  };

  WalkListing.prototype.accept = function(rx, ctx) {
    return this.selectEx(function(e) {
      return e.accept(rx, ctx);
    });
  };

  WalkListing.prototype.reject = function(rx, ctx) {
    return this.selectEx(function(e) {
      return e.reject(rx, ctx);
    });
  };

  WalkListing.prototype.inspect = function() {
    return this.toJSON();
  };

  WalkListing.prototype.toJSON = function() {
    var e, res, _i, _len, _name, _ref;
    res = {
      path: this.path,
      relPath: this.relPath
    };
    _ref = this.select();
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      e = _ref[_i];
      (res[_name = e.mode + 's'] || (res[_name] = [])).push(e.name);
    }
    return res;
  };

  return WalkListing;

})();

createTaskQueue = function(opt) {
  var finish, idleFns, invokeEach, isIdle, live, nActive, nComplete, nMaxTasks, nextTick, queueTask, runTasks, schedule, self, taskq, updateFns;
  if (opt == null) {
    opt = {};
  }
  nextTick = opt.schedule || process.nextTick;
  nMaxTasks = opt.tasks || 9e9;
  nComplete = 0;
  nActive = 0;
  taskq = [];
  live = false;
  self = queueTask = function(outer, inner) {
    var inner_finish;
    if (inner != null) {
      inner_finish = function() {
        finish();
        return inner.apply(null, arguments);
      };
    } else {
      inner_finish = finish;
    }
    taskq.push(function() {
      return outer(inner_finish);
    });
    return schedule();
  };
  Object.defineProperties(self, {
    active: {
      get: function() {
        return nActive;
      }
    },
    total: {
      get: function() {
        return nActive + taskq.length;
      }
    },
    incomplete: {
      get: function() {
        return taskq.length;
      }
    },
    complete: {
      get: function() {
        return nComplete;
      }
    }
  });
  finish = function() {
    ++nComplete;
    --nActive;
    schedule();
  };
  schedule = function() {
    if (!live++) {
      nextTick(runTasks);
    }
    return self;
  };
  runTasks = function() {
    live = false;
    while (taskq.length && nActive <= nMaxTasks) {
      try {
        nActive++;
        taskq.shift()();
      } catch (err) {
        nActive--;
        self.error(err);
      }
    }
    updateFns.invoke(self, nActive, taskq.length);
    if (isIdle()) {
      idleFns.invoke(self);
    }
  };
  self.isIdle = isIdle = function(min) {
    return (0 === nActive) && (0 === taskq.length) && (!(min != null) || min <= nComplete);
  };
  self.throttle = function(n) {
    nMaxTasks = n;
    return schedule();
  };
  self.error = opt.error || function(err) {
    return console.error(err.stack);
  };
  invokeEach = function() {
    var fn, _i, _len, _results;
    _results = [];
    for (_i = 0, _len = this.length; _i < _len; _i++) {
      fn = this[_i];
      try {
        _results.push(fn.apply(null, arguments));
      } catch (err) {
        _results.push(self.error(err));
      }
    }
    return _results;
  };
  (updateFns = []).invoke = invokeEach;
  self.update = function(callback) {
    updateFns.push(callback);
  };
  (idleFns = []).invoke = invokeEach;
  self.idle = function(callback) {
    idleFns.push(callback);
    if (isIdle()) {
      return callback(self);
    }
  };
  return self;
};

WalkNode = (function() {

  WalkNode.prototype.WalkEntry = WalkEntry;

  WalkNode.prototype.WalkListing = WalkListing;

  function WalkNode(root, opt) {
    Object.defineProperties(this, {
      root: {
        value: root
      },
      walkQueue: {
        value: createTaskQueue()
      },
      _fs_queue: {
        value: createTaskQueue({
          tasks: opt.tasks || 10
        })
      }
    });
  }

  WalkNode.prototype.create = function(listPath, entry, target) {
    listPath = path.resolve(listPath);
    return Object.create(this, {
      listPath: {
        value: listPath
      },
      rootPath: {
        value: (entry != null ? entry.rootPath : void 0) || listPath
      },
      entry: {
        value: entry
      },
      target: {
        value: target
      }
    });
  };

  WalkNode.prototype.newEntry = function() {
    return new this.WalkEntry(this);
  };

  WalkNode.prototype.newListing = function(pathOrEntry, target) {
    var self;
    if (typeof pathOrEntry.isWalkable === "function" ? pathOrEntry.isWalkable() : void 0) {
      self = this.create((typeof pathOrEntry.walkPath === "function" ? pathOrEntry.walkPath() : void 0) || pathOrEntry.path, pathOrEntry, target);
    } else {
      self = this.create(pathOrEntry, null, target);
    }
    return new this.WalkListing(self);
  };

  WalkNode.prototype.walk = function(pathOrEntry, target) {
    var listing;
    listing = this.newListing(pathOrEntry, target);
    this.walkQueue(function(done) {
      return listing._performListing(target, done);
    });
    return listing;
  };

  WalkNode.prototype.resolve = function() {
    var args;
    args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    return path.resolve.apply(path, [this.listPath].concat(__slice.call(args)));
  };

  WalkNode.prototype.relative = function() {
    var args;
    args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    return path.relative.apply(path, [this.rootPath].concat(__slice.call(args)));
  };

  WalkNode.prototype.addEntryFilter = function() {
    var fns;
    fns = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    return this.entryFilters = (this.entryFilters || []).concat(fns);
  };

  WalkNode.prototype.filterEntry = function(entry) {
    var fn, _i, _len, _ref, _results;
    if (this.entryFilters != null) {
      _ref = this.entryFilters;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        fn = _ref[_i];
        try {
          _results.push(fn(entry));
        } catch (err) {

        }
      }
      return _results;
    }
  };

  WalkNode.prototype._fs_stat = function(aPath, callback) {
    return this._fs_queue(function(next) {
      return fs.stat(aPath, next);
    }, callback);
  };

  WalkNode.prototype._fs_readdir = function(aPath, callback) {
    return this._fs_queue(function(next) {
      return fs.readdir(aPath, next);
    }, callback);
  };

  return WalkNode;

})();

WalkRoot = (function(_super) {

  __extends(WalkRoot, _super);

  WalkRoot.prototype.WalkNode = WalkNode;

  function WalkRoot(opt) {
    var _this = this;
    if (opt == null) {
      opt = {};
    }
    events.EventEmitter.call(this);
    this.node = new this.WalkNode(this, opt);
    this.node.walkQueue.idle(function(q) {
      if (q.complete > 0) {
        return _this.emit('done');
      }
    });
    if (!opt.showHidden) {
      this.reject(/^\./);
    }
    if (opt.autoWalk != null) {
      this.autoWalk = opt.autoWalk || (function() {
        return null;
      });
    }
  }

  WalkRoot.prototype.walk = function(pathOrEntry, target) {
    if (target == null) {
      target = this;
    }
    return this.node.walk(pathOrEntry, target || this);
  };

  WalkRoot.prototype.autoWalk = function(entry, target) {
    return entry.walk(target);
  };

  WalkRoot.prototype.isDone = function() {
    return this.node.walkQueue.isIdle(1);
  };

  WalkRoot.prototype.done = function(callback) {
    if (!this.isDone()) {
      this.on('done', callback);
    } else {
      callback();
    }
    return this;
  };

  WalkRoot.prototype.filter = function() {
    var args;
    args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    this.node.addEntryFilter(function(e) {
      if (args[0] != null) {
        return e.filter.apply(e, args);
      }
    });
    return this;
  };

  WalkRoot.prototype.accept = function() {
    var args;
    args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    this.node.addEntryFilter(function(e) {
      if (args[0] != null) {
        return e.accept.apply(e, args);
      }
    });
    return this;
  };

  WalkRoot.prototype.reject = function() {
    var args;
    args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    this.node.addEntryFilter(function(e) {
      if (args[0] != null) {
        return e.reject.apply(e, args);
      }
    });
    return this;
  };

  return WalkRoot;

})(events.EventEmitter);

tromp = function(path, opt, callback) {
  var root;
  if (typeof opt === 'function') {
    callback = opt;
    opt = null;
  }
  if (typeof path === !'string') {
    opt = path;
    path = null;
  }
  root = new tromp.WalkRoot(opt);
  if (callback != null) {
    root.on('listing', callback);
  }
  path || (path = opt != null ? opt.path : void 0);
  if (path != null) {
    root.walk(path);
  }
  return root;
};

tromp.WalkRoot = WalkRoot;

tromp.WalkNode = WalkNode;

tromp.WalkEntry = WalkEntry;

tromp.WalkListing = WalkListing;

module.exports = tromp.tromp = tromp;
