var tromp = require('../tromp'),
    path = require('path'),
    testDir = path.join(__dirname, '..'),
    testObj;

testObj = tromp(testDir)
  .reject(/node_modules|build|dist/)
  .on('listed', function (node) {
    console.log({
      base: node.base(),
      files: node.files(),
      dirs: node.dirs()})
  })
  .on('active', function (active) {
      console.log('active?', active)
  })

if (1)
  testObj.queueTask.report = function(nTasks, n, fnq) {
    console.log('taskQueue:', nTasks, n, fnq) }

if (0)
  testObj.walk(path.join(__dirname, '../..'))
