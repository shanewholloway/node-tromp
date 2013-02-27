var tromp = require('../tromp'),
    path = require('path'),
    testDir = path.join(__dirname, '..'),
    testWalker;

testWalker = tromp(testDir)
  .reject(/node_modules|build|dist/)
  .on('file', function (entry) { console.log('evt file:', entry) })
  .on('dir', function (entry) { console.log('evt dir:', entry) })
  .on('listed', function (listing) { console.log('evt listed:', listing.inspect()) })
  .done(function() { console.log('callback done') })

if (0)
  testWalker.queueTask.report = function(nTasks, n, fnq) {
    console.log('taskQueue:', nTasks, n, fnq) }

if (0)
  testWalker.walk(path.join(__dirname, '../..'))
