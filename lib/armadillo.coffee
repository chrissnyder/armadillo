{EventEmitter} = require 'events'

async = require 'async'
request = require 'request'
phantom = require 'node-phantom'

class Armadillo extends EventEmitter

  project: ''
  bucket: ''

  host: 'https://dev.zooniverse.org'
  json: 'offline/subjects.json'

  limit: 3
  subjects: []

  options: null

  constructor: (params = {}) ->
    @[property] = value for own property, value of params when property of @

    # S3
    @s3 = require('knox').createClient
      key: @options.key || process.env.S3_ACCESS_ID
      secret: @options.secret || process.env.S3_SECRET_KEY
      bucket: @bucket

  go: =>
    async.auto
      getHost: @getHost
      getSubjects: ['getHost', @getSubjects]
      save: ['getSubjects', @save]
    , (err) =>
      if err
        console.log 'Error:', err

      process.exit()

  # In general order of calling
  getHost: (callback) =>
    phantom.create (err, ph) =>
      ph.createPage (err, page) =>
        page.open @url(), (err, status) =>
          if err
            ph.exit()
            callback err, null
            return

          page.evaluate ->
            return window.zooniverse.Api.current.proxyFrame.host
          , (err, @host) ->
            ph.exit()

            if err
              callback err, null
              return

            callback null, @host

  getSubjects: (callback) =>
    options = 
      url: "#{ @host }/projects/#{ @project }/subjects"
      qs:
        limit: @limit
      strictSSL: false

    request options, (err, res, rawSubjects) =>
      if err
        callback err, null
        return

      for subject in JSON.parse(rawSubjects)
        @subjects.push subject

      callback null, @subjects

  save: (callback) =>
    buffer = new Buffer JSON.stringify @subjects

    headers =
      'x-amz-acl': 'public-read'
      'Content-Type': 'application/json'

    @s3.putBuffer buffer, @json, headers, (err, res) ->
      if err
        callback err, null
        return

      callback null, res

  url: =>
    # Attempt to derive the url from the bucket
    if @bucket is 'zooniverse-demo'
      "http://zooniverse-demo.s3-website-us-east-1.amazonaws.com"
    else
      "http://#{ @bucket }"

module.exports = Armadillo