const { environment } = require('@rails/webpacker')
const { VueLoaderPlugin } = require('vue-loader')
const vue = require('./loaders/vue')

environment.plugins.prepend('VueLoaderPlugin', new VueLoaderPlugin())
environment.loaders.prepend('vue', vue)
environment.config.merge({
  resolveLoader: {
    modules: ['node_modules', require('path').join(require.resolve('@rails/webpacker/package.json'), '..', 'node_modules')]
  }
})
module.exports = environment
