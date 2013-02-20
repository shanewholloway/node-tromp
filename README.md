Tromp is an asynchronous filesystem directory walking algorithm with events and accept/reject filtering. For use with `minimatch` or other filtering tools.

## Use

```javascript

var tromp = require('tromp')

tromp('.')
  .reject(/node_modules/)
  .on('listed', function (node) {
    console.log({
      base: node.base(),
      files: node.files(),
      dirs: node.dirs()})
  })

```
