var tromp = require('../tromp')

tromp('.')
  .reject(/node_modules/)
  .on('listed', function (listing) {
    console.log(listing.inspect()) })
