// Generated by CoffeeScript 1.4.0
var WalkEntry, WalkListing, WalkNode, WalkRoot, createTaskQueue, events, fs, path, tromp,
  __slice = [].slice,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

fs = require('fs');

path = require('path');

events = require('events');

WalkEntry = (function() {

  function WalkEntry(node) {
    Object.defineProperty(this, 'node', {
      value: node,
      enumerable: false
    });
  }

  WalkEntry.prototype.create = function(name) {
    return Object.create(this, {
      name: {
        value: name
      }
    });
  };

  WalkEntry.prototype.path = function() {
    return this.node.resolve(this.name);
  };

  WalkEntry.prototype.relPath = function() {
    return this.node.relative(this.path());
  };

  WalkEntry.prototype.rootPath = function() {
    return this.node.rootPath;
  };

  WalkEntry.prototype.modeKey = function() {
    var stat;
    stat = this.stat;
    if (!(stat != null)) {
      return 'unknown';
    }
    if (stat.isFile()) {
      return 'file';
    }
    if (stat.isDirectory()) {
      return 'dir';
    }
    return 'other';
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

  WalkEntry.prototype.walk = function(force) {
    if (this.isWalkable(force)) {
      return this.node.root.walk(this.path(), this);
    }
  };

  WalkEntry.prototype.toString = function() {
    return this.path();
  };

  WalkEntry.prototype.toJSON = function() {
    return this.toString();
  };

  WalkEntry.prototype.valueOf = function() {
    return this.toString();
  };

  WalkEntry.prototype.inspect = function() {
    return this.relPath();
  };

  return WalkEntry;

})();

WalkListing = (function() {

  function WalkListing(node) {
    Object.defineProperty(this, 'node', {
      value: node,
      enumerable: false
    });
  }

  WalkListing.prototype.path = function() {
    return this.node.resolve();
  };

  WalkListing.prototype.relPath = function() {
    return this.node.relative(this.path());
  };

  WalkListing.prototype.rootPath = function() {
    return this.node.rootPath;
  };

  WalkListing.prototype._performListing = function(root, done) {
    var entry, self;
    if (this._entries === !void 0) {
      return false;
    }
    self = this;
    this._entries = null;
    entry = new this.node.WalkEntry(this.node);
    root._fs_readdir(this.path(), function(err, entries) {
      var n;
      if (err != null) {
        if (typeof root.error === "function") {
          root.error('fs.readdir', err, self);
        }
      }
      entries = (entries || []).map(function(e) {
        return entry.create(e);
      });
      self._entries = entries;
      root.emit('listing', self);
      n = entries.length;
      return entries.forEach(function(entry) {
        return root._fs_stat(entry.path(), function(err, stat) {
          Object.defineProperty(entry, 'stat', {
            value: stat,
            enumerable: false
          });
          if (err != null) {
            if (typeof root.error === "function") {
              root.error('fs.stat', err, entry, self);
            }
          }
          if (stat != null) {
            root.emit('filter', entry, self);
            if (!entry.excluded) {
              root.emit('entry', entry, self);
              root.emit(entry.modeKey(), entry, self);
              if (entry.isWalkable()) {
                root.autoWalk(entry);
              }
            }
          }
          if (--n === 0) {
            root.emit('listed', self);
            return typeof done === "function" ? done(self) : void 0;
          }
        });
      });
    });
    return self;
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

  WalkListing.prototype.walk = function() {
    var d, opts, _i, _len, _ref;
    opts = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    opts.unshift(function(e) {
      return e.isDirectory();
    });
    _ref = this.select.apply(this, opts);
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      d = _ref[_i];
      d.walk();
    }
    return this;
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
      path: this.path(),
      relPath: this.relPath()
    };
    _ref = this.select();
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      e = _ref[_i];
      (res[_name = e.modeKey() + 's'] || (res[_name] = [])).push(e.name);
    }
    return res;
  };

  return WalkListing;

})();

createTaskQueue = function(nTasks, schedule) {
  var fnq, n, queueTask, step, _active;
  if (schedule == null) {
    schedule = process.nextTick;
  }
  n = 0;
  fnq = [];
  _active = false;
  step = function(c) {
    if (c != null) {
      n -= c;
      if (!_active) {
        _active = true;
        schedule(step);
      }
    } else {
      _active = false;
      while (fnq.length && n <= nTasks) {
        try {
          n++;
          fnq.shift()();
        } catch (err) {
          n--;
        }
      }
      if (typeof queueTask.report === "function") {
        queueTask.report(nTasks, n, fnq.length);
      }
    }
    return nTasks - n - fnq.length;
  };
  queueTask = function(inner, outer) {
    fnq.push(outer.bind(this, function() {
      step(1);
      return inner.apply(this, arguments);
    }));
    return step(0);
  };
  queueTask.clear = function() {
    fnq.length = 0;
    return step(0);
  };
  queueTask.throttle = function(n) {
    nTasks = n;
    return step(0);
  };
  return queueTask;
};

WalkNode = (function() {

  WalkNode.prototype.WalkListing = WalkListing;

  WalkNode.prototype.WalkEntry = WalkEntry;

  function WalkNode(root) {
    Object.defineProperties(this, {
      root: {
        value: root,
        enumerable: false
      }
    });
  }

  WalkNode.prototype.create = function(listPath, entry) {
    return Object.create(this, {
      listPath: {
        value: listPath
      },
      rootPath: {
        value: (entry != null ? entry.rootPath() : void 0) || listPath
      },
      entry: {
        value: entry
      }
    });
  };

  WalkNode.prototype._performListing = function(done) {
    return new this.WalkListing(this)._performListing(this.root, done);
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

  return WalkNode;

})();

WalkRoot = (function(_super) {

  __extends(WalkRoot, _super);

  WalkRoot.prototype.WalkNode = WalkNode;

  function WalkRoot(path, opt, callback) {
    var _this = this;
    events.EventEmitter.call(this);
    if ('function' === typeof opt) {
      callback = opt;
      opt = {};
    } else {
      opt || (opt = {});
    }
    if (callback != null) {
      this.on('listed', callback);
    }
    if (!opt.showHidden) {
      this.reject(/^\./);
    }
    if (opt.autoWalk != null) {
      this.autoWalk = opt.autoWalk || (function() {
        return null;
      });
    }
    opt.schedule || (opt.schedule = process.nextTick);
    this._activeWalks = [0];
    this._node = new this.WalkNode(this);
    this.queueTask = createTaskQueue(opt.tasks || 10, opt.schedule);
    if (path != null) {
      opt.schedule(function() {
        return _this.walk(path);
      });
    }
    return this;
  }

  WalkRoot.prototype.walk = function(aPath, entry) {
    var node, track,
      _this = this;
    if (typeof aPath.isWalkable === "function" ? aPath.isWalkable() : void 0) {
      entry = aPath;
      aPath = entry.path();
    }
    aPath = path.resolve(aPath);
    track = this._activeWalks;
    if (__indexOf.call(track, aPath) < 0) {
      track[aPath] = node = this._node.create(aPath, entry);
      if (track[0] === 0) {
        this.emit('start');
      }
      this.emit('active', ++track[0], +1, track);
      return node._performListing(function() {
        delete track[aPath];
        _this.emit('active', --track[0], -1, track);
        if (track[0] === 0) {
          return _this.emit('done');
        }
      });
    }
  };

  WalkRoot.prototype.autoWalk = function(entry) {
    return entry.walk();
  };

  WalkRoot.prototype.filter = function(rx, ctx) {
    if (rx != null) {
      this.on('filter', function(e) {
        return e.filter(rx, ctx);
      });
    }
    return this;
  };

  WalkRoot.prototype.accept = function(rx, ctx) {
    if (rx != null) {
      this.on('filter', function(e) {
        return e.accept(rx, ctx);
      });
    }
    return this;
  };

  WalkRoot.prototype.reject = function(rx, ctx) {
    if (rx != null) {
      this.on('filter', function(e) {
        return e.reject(rx, ctx);
      });
    }
    return this;
  };

  WalkRoot.prototype._fs_stat = function(aPath, cb) {
    return this.queueTask(cb, function(cb) {
      return fs.stat(aPath, cb);
    });
  };

  WalkRoot.prototype._fs_readdir = function(aPath, cb) {
    return this.queueTask(cb, function(cb) {
      return fs.readdir(aPath, cb);
    });
  };

  return WalkRoot;

})(events.EventEmitter);

tromp = function(path, opt, callback) {
  return new tromp.WalkRoot(path, opt, callback);
};

tromp.WalkRoot = WalkRoot;

tromp.WalkNode = WalkNode;

tromp.WalkEntry = WalkEntry;

tromp.WalkListing = WalkListing;

module.exports = tromp.tromp = tromp;
