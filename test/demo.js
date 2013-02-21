var tromp = require('../tromp'),
    path = require('path'),
    testDir = path.join(__dirname, '..'),
    testObj;

testObj = tromp(testDir)
  .reject(/node_modules|build|dist/)
  .on('file', function (entry) {
    console.log('evt file:', entry)
  })
  .on('dir', function (entry) {
    console.log('evt dir:', entry)
  })
  .on('listed', function (node) {
    console.log('evt listed:', node.toJSON())
  })
  .on('active', function (active, delta) {
      console.log('evt active:', active, delta)
  })

if (0)
  testObj.queueTask.report = function(nTasks, n, fnq) {
    console.log('taskQueue:', nTasks, n, fnq) }

if (0)
  testObj.walk(path.join(__dirname, '../..'))
