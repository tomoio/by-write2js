fs = require('fs')
coffee = require('coffee-script')
EventEmitter = require('events').EventEmitter
colors = require('colors')
path = require('path')
util = require('util')
_ = require('underscore')
minimatch = require('minimatch')

module.exports = class ByWrite2JS extends EventEmitter

  constructor: (@opts = {}) ->
    @mapper = @opts?.mapper ? {}
    @opts.bin ?= false
    @opts.binDir ?= "#{@opts.root}/bin"

  _setListeners: (@bystander) ->
    @bystander.by.coffeescript.on('compiled', (data) =>
        data.jsfile = @_getJSPath(data.file, @mapper)
        @_writeJS(data)
    )
    @bystander.by.coffeescript.on('coffee removed', (file) =>
      jsfile = @_getJSPath(file, @mapper)
      @rmJS({file: file, jsfile: jsfile})
    )

  # #### Replace file extension
  # `txt (String)` : a file path to replace  
  # `ext (String)` : a new extension to replace with
  _replaceExt: (txt, ext = 'js') ->
    return txt.replace(/\.coffee$/, "." + ext)

  # #### Get destination jsfile path to save compiled JS code to
  # `csfile (String)` : a path to the original CoffeeScript file  
  # `mapper (Object)` : rules to map `csfile` path to output js file path 
  _getJSPath: (csfile, mapper = {}) ->
    filebase = path.basename(csfile)
    dirname = path.dirname(csfile)
    dirdir = path.dirname(dirname)
    basename = path.basename(dirname)
    if @opts.bin and filebase.match(/\.bin\.coffee$/i) isnt null
      return "#{@opts.binDir}/" + filebase.replace(/\.bin\.coffee$/i,'')
    if typeof(mapper) is 'object' and not util.isArray(mapper)
      for k, v of mapper
        try
          m = minimatch(csfile, k)
          if m
            if util.isArray(v)
              return @_replaceExt(path.normalize(csfile.replace(v[0],v[1])))
            else if typeof(v) is 'function'
              return @_replaceExt(path.normalize(v(csfile)))
        catch e
    return "#{dirname}/" + @_replaceExt(filebase)

  # #### Write compiled code to JS file
  _writeJS: (data) ->
    version = '// Generated by CoffeeScript ' + coffee.VERSION
    if @opts.bin and data.file.match(/\.bin\.coffee$/i) isnt null
      version = '#!/usr/bin/env node'
    fs.writeFile(data.jsfile, [version, data.compiled].join('\n'), (err) =>
      @_emitter(err, data)
    )

  # #### Emit an event based on JS writeErr, pass on lint result
  _emitter: (writeErr, data) ->
    if writeErr
      @_emitWriteError(writeErr,data)
    else
      @_emitWrote(data)

  # #### Emit compiled event with lint result
  _emitWrote: (data) ->
    @emit(
      'wrote2js',
      {file: data.file, jsfile: data.jsfile, compiled: data.compiled, code: data.code}
    )
    unless @opts.nolog
      console.log("#{data.file} => #{data.jsfile}".grey + '\n')

  # #### Emit write error event with lint result
  _emitWriteError: (err, data) ->
    message = [
      'fail to write js file'.yellow,
      " - #{data.file}",
      " -> #{data.jsfile}"
    ]
    unless @opts.nolog
      console.log(message.join(''), '\n')
    @emit(
      'write2js error',
      {file: data.file, jsfile: data.jsfile, err: err, compiled: data.compiled, code: data.code}
    )

  # #### Remove the destination JS file and emit an event accordingly
  rmJS: (data) ->
    fs.unlink(data.jsfile, (err) =>
      if err
        @emit(
          'unlink error',
          {file: data.file, jsfile: data.jsfile, err: err}
        )
      else
        @emit(
          'js removed',
          data
        )
    )