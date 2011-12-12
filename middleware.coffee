# Load dependencies.
file = require 'fs'
uglify = require 'uglify-js'
jade = require 'jade'
uparse = require('url').parse

# Get parser and uglifier
jsp = uglify.parser
pro = uglify.uglify

# Export closure to build middleware.
module.exports = (opts) ->
  live = !!process.env.PRODUCTION
  if typeof opts.live is 'undefined' then opts.live = !live

  # Return the middleware
  (req, res, next) ->
    # Parse pathname from URL.
    url = uparse(req.url, true)

    # Make sure the current URL ends in either .coffee or .js
    if !~url.pathname.search(/\.jade\.js$/) then do next
    else
      nfile = opts.path + url.pathname
      ofile = nfile.replace(/\.js$/, '')
      name = ofile.substr(ofile.lastIndexOf('/')+1, ofile.lastIndexOf('.')-ofile.lastIndexOf('/')-1)
      
      # Yup, we have to (re)compile.
      compile = ->
        file.readFile ofile, (err, ndata) ->
          if err then do next
          else
            # Don't crash the server just because a compile failed.
            try
              # Attempt to compile to Javascript.
              ntxt = jade.compile do ndata.toString, client: true
              ntxt = do ntxt.toString
              if url.query.action then ntxt = url.query.action+'('+ntxt+');'
              else ntxt = "this.templates=this.templates||{};this.templates['"+name+"']="+ntxt

              # Ugligfy.
              ast = jsp.parse ntxt
              ast = pro.ast_mangle ast
              ast = pro.ast_squeeze ast
              ntxt = pro.gen_code ast
              
              # Save to file. Make new directory, if necessary.
              path = ofile.substr 0, ofile.lastIndexOf '/'
              file.stat path, (err, stat) ->
                save = -> file.writeFile nfile, ntxt, next
                if not err and stat.isDirectory() then do save
                else file.mkdir path, 0666, save
            
            # Continue on errors.
            catch err #then do next
              throw new Error err
      
      # Check for existence.
      file.stat nfile, (err, nstat) ->
        if err then do compile
        else if not opts.live then do next
        else
          # Get mod date of .jade.js file.
          file.stat nfile, (err, nstat) ->
            if err then do next
            else
              # Get mod date of .jade file.
              ntime = do (new Date nstat.mtime).getTime
              file.stat ofile, (err, ostat) ->
                if err then do next
                else
                  # Compare mod dates.
                  otime = do (new Date ostat.mtime).getTime
                  if ntime >= otime then do next
                  else do compile
